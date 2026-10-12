package store

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/smithy-go"

	"github.com/pedro-santiago/toret/backend/internal/httpx"
)

// DynamoAPI is the part of *dynamodb.Client the store uses; tests record calls
// with a stub.
type DynamoAPI interface {
	GetItem(ctx context.Context, in *dynamodb.GetItemInput, opts ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error)
	PutItem(ctx context.Context, in *dynamodb.PutItemInput, opts ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error)
	DeleteItem(ctx context.Context, in *dynamodb.DeleteItemInput, opts ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error)
	UpdateItem(ctx context.Context, in *dynamodb.UpdateItemInput, opts ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error)
	Query(ctx context.Context, in *dynamodb.QueryInput, opts ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error)
	TransactWriteItems(ctx context.Context, in *dynamodb.TransactWriteItemsInput, opts ...func(*dynamodb.Options)) (*dynamodb.TransactWriteItemsOutput, error)
}

// Dynamo is the DynamoDB-backed Store. Every attribute name in every
// expression goes through ExpressionAttributeNames, so none can collide with a
// reserved word (date, ttl, hidden and note all are).
type Dynamo struct {
	DB    DynamoAPI
	Table string
}

type item = map[string]types.AttributeValue

func s(v string) types.AttributeValue { return &types.AttributeValueMemberS{Value: v} }
func n(v int64) types.AttributeValue {
	return &types.AttributeValueMemberN{Value: strconv.FormatInt(v, 10)}
}
func b(v bool) types.AttributeValue { return &types.AttributeValueMemberBOOL{Value: v} }
func nf(v float64) types.AttributeValue {
	return &types.AttributeValueMemberN{Value: strconv.FormatFloat(v, 'f', -1, 64)}
}

func str(it item, k string) string {
	if v, ok := it[k].(*types.AttributeValueMemberS); ok {
		return v.Value
	}
	return ""
}

func num(it item, k string) (float64, bool) {
	if v, ok := it[k].(*types.AttributeValueMemberN); ok {
		f, err := strconv.ParseFloat(v.Value, 64)
		return f, err == nil
	}
	return 0, false
}

func flag(it item, k string) bool {
	v, ok := it[k].(*types.AttributeValueMemberBOOL)
	return ok && v.Value
}

func when(it item, k string) time.Time {
	t, err := httpx.ParseTime(str(it, k))
	if err != nil {
		return time.Time{}
	}
	return t
}

func (d *Dynamo) pk(pk, sk string) item { return item{"pk": s(pk), "sk": s(sk)} }

func reportKey(id string) item { return item{"pk": s("REPORT#" + id), "sk": s("META")} }

// unavailable maps throttling and transport failures to ErrUnavailable.
func unavailable(err error) error {
	if err == nil {
		return nil
	}
	var api smithy.APIError
	if errors.As(err, &api) {
		switch api.ErrorCode() {
		case "ProvisionedThroughputExceededException", "ThrottlingException", "RequestLimitExceeded",
			"InternalServerError", "ServiceUnavailable", "TransactionInProgressException":
			return fmt.Errorf("%w: %v", ErrUnavailable, err)
		}
		return err
	}
	return fmt.Errorf("%w: %v", ErrUnavailable, err)
}

func isConditionFailed(err error) bool {
	var c *types.ConditionalCheckFailedException
	return errors.As(err, &c)
}

// ---- reports ---------------------------------------------------------------

func marshalReport(r Record) item {
	key := DateKey(r.Date, r.ID)
	fountainKey := "FOUNTAIN#" + r.FountainID
	tags := make([]types.AttributeValue, len(r.Tags))
	for i, t := range r.Tags {
		tags[i] = s(t)
	}
	it := reportKey(r.ID)
	it["id"], it["fountainID"], it["state"] = s(r.ID), s(r.FountainID), s(r.State)
	if r.Rating != nil {
		it["rating"] = n(int64(*r.Rating))
	}
	it["tags"] = &types.AttributeValueMemberL{Value: tags}
	it["note"] = s(r.Note)
	it["date"], it["createdAt"] = s(httpx.FormatTime(r.Date)), s(httpx.FormatTime(r.CreatedAt))
	it["author"], it["installHash"] = s(r.Author), s(r.InstallHash)
	it["flagCount"] = n(int64(r.FlagCount))
	it["dateKey"], it["fountainKey"] = s(key), s(fountainKey)
	it["gsi1pk"], it["gsi1sk"] = s("FEED"), s(key)
	it["gsi2pk"], it["gsi2sk"] = s(fountainKey), s(key)
	it["ttl"] = n(Expiry(r.Date).Unix())
	return it
}

func unmarshalReport(it item) Record {
	r := Record{
		ID:          str(it, "id"),
		FountainID:  str(it, "fountainID"),
		State:       str(it, "state"),
		Note:        str(it, "note"),
		Date:        when(it, "date"),
		CreatedAt:   when(it, "createdAt"),
		Author:      str(it, "author"),
		InstallHash: str(it, "installHash"),
		Hidden:      flag(it, "hidden"),
		HiddenBy:    str(it, "hiddenBy"),
		Reviewed:    flag(it, "reviewed"),
		Tags:        []string{},
	}
	if v, ok := num(it, "rating"); ok {
		i := int(v)
		r.Rating = &i
	}
	if v, ok := num(it, "flagCount"); ok {
		r.FlagCount = int(v)
	}
	if l, ok := it["tags"].(*types.AttributeValueMemberL); ok {
		for _, t := range l.Value {
			if tv, ok := t.(*types.AttributeValueMemberS); ok {
				r.Tags = append(r.Tags, tv.Value)
			}
		}
	}
	return r
}

func (d *Dynamo) GetReport(ctx context.Context, id string) (*Record, error) {
	out, err := d.DB.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: &d.Table, Key: reportKey(id), ConsistentRead: ptr(true),
	})
	if err != nil {
		return nil, unavailable(err)
	}
	if len(out.Item) == 0 {
		return nil, nil
	}
	r := unmarshalReport(out.Item)
	return &r, nil
}

func (d *Dynamo) PutReport(ctx context.Context, r Record) (bool, error) {
	_, err := d.DB.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:                &d.Table,
		Item:                     marshalReport(r),
		ConditionExpression:      ptr("attribute_not_exists(#pk)"),
		ExpressionAttributeNames: map[string]string{"#pk": "pk"},
	})
	if isConditionFailed(err) {
		return false, nil
	}
	if err != nil {
		return false, unavailable(err)
	}
	return true, nil
}

func (d *Dynamo) DeleteReport(ctx context.Context, id, installHash string) (DeleteOutcome, error) {
	_, err := d.DB.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName:                           &d.Table,
		Key:                                 reportKey(id),
		ConditionExpression:                 ptr("#owner = :owner"),
		ExpressionAttributeNames:            map[string]string{"#owner": "installHash"},
		ExpressionAttributeValues:           item{":owner": s(installHash)},
		ReturnValuesOnConditionCheckFailure: types.ReturnValuesOnConditionCheckFailureAllOld,
	})
	if err == nil {
		return Deleted, nil
	}
	var c *types.ConditionalCheckFailedException
	if errors.As(err, &c) {
		// The condition fails both for a missing item and for someone else's;
		// ALL_OLD tells them apart.
		if len(c.Item) == 0 {
			return NotFound, nil
		}
		return NotOwner, nil
	}
	return NotFound, unavailable(err)
}

func (d *Dynamo) query(ctx context.Context, index, pkName, skName, pkValue string, cutoff time.Time, limit int) ([]Record, error) {
	var out []Record
	var start item
	for len(out) < limit {
		res, err := d.DB.Query(ctx, &dynamodb.QueryInput{
			TableName:                 &d.Table,
			IndexName:                 &index,
			KeyConditionExpression:    ptr("#p = :p AND #s > :c"),
			ExpressionAttributeNames:  map[string]string{"#p": pkName, "#s": skName},
			ExpressionAttributeValues: item{":p": s(pkValue), ":c": s(CutoffKey(cutoff))},
			ScanIndexForward:          ptr(false),
			Limit:                     ptr(int32(limit - len(out))),
			ExclusiveStartKey:         start,
		})
		if err != nil {
			return nil, unavailable(err)
		}
		for _, it := range res.Items {
			out = append(out, unmarshalReport(it))
		}
		if len(res.LastEvaluatedKey) == 0 {
			break
		}
		start = res.LastEvaluatedKey
	}
	return out, nil
}

func (d *Dynamo) Feed(ctx context.Context, cutoff time.Time, limit int) ([]Record, error) {
	return d.query(ctx, "gsi1", "gsi1pk", "gsi1sk", "FEED", cutoff, limit)
}

func (d *Dynamo) Fountain(ctx context.Context, fountainID string, cutoff time.Time, limit int) ([]Record, error) {
	return d.query(ctx, "gsi2", "gsi2pk", "gsi2sk", "FOUNTAIN#"+fountainID, cutoff, limit)
}

func (d *Dynamo) Banned(ctx context.Context, installHash string) (bool, error) {
	out, err := d.DB.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: &d.Table, Key: d.pk("BAN#"+installHash, "BAN"),
	})
	if err != nil {
		return false, unavailable(err)
	}
	return len(out.Item) > 0, nil
}

// ---- flags -------------------------------------------------------------------

const flagAttempts = 3

func (d *Dynamo) Flag(ctx context.Context, f FlagRequest) (FlagOutcome, error) {
	for attempt := 0; attempt < flagAttempts; attempt++ {
		rec, err := d.GetReport(ctx, f.ReportID)
		if err != nil {
			return FlagIgnored, err
		}
		if rec == nil || rec.Hidden || rec.InstallHash == f.InstallHash {
			return FlagIgnored, nil
		}
		hide := rec.FlagCount+1 >= HideThreshold && !rec.Reviewed
		_, err = d.DB.TransactWriteItems(ctx, d.flagTransaction(f, rec, hide))
		if err == nil {
			if hide {
				return FlagCountedAndHidden, nil
			}
			return FlagCounted, nil
		}
		var cancelled *types.TransactionCanceledException
		if !errors.As(err, &cancelled) {
			return FlagIgnored, unavailable(err)
		}
		if reasonCode(cancelled, 0) == "ConditionalCheckFailed" || reasonCode(cancelled, 1) == "ConditionalCheckFailed" {
			// A flag item already exists: this install or this address flagged it.
			return FlagDuplicate, nil
		}
		// flagCount moved (or a concurrent transaction): read again and retry.
	}
	return FlagIgnored, fmt.Errorf("%w: flag contended", ErrUnavailable)
}

func reasonCode(e *types.TransactionCanceledException, i int) string {
	if i < len(e.CancellationReasons) && e.CancellationReasons[i].Code != nil {
		return *e.CancellationReasons[i].Code
	}
	return ""
}

// flagTransaction is the three-item transaction of api.md section 8.2.
func (d *Dynamo) flagTransaction(f FlagRequest, rec *Record, hide bool) *dynamodb.TransactWriteItemsInput {
	ttl := n(Expiry(rec.Date).Unix())
	created := s(httpx.FormatTime(f.Now))
	noFlag := ptr("attribute_not_exists(#pk)")
	names := map[string]string{"#pk": "pk"}

	update := "ADD #fc :one"
	metaNames := map[string]string{"#fc": "flagCount", "#h": "hidden"}
	metaValues := item{":one": n(1), ":seen": n(int64(rec.FlagCount))}
	if hide {
		update = "SET #h = :true, #hb = :flags ADD #fc :one REMOVE #g1p, #g1s, #g2p, #g2s"
		metaNames["#hb"] = "hiddenBy"
		metaNames["#g1p"], metaNames["#g1s"] = "gsi1pk", "gsi1sk"
		metaNames["#g2p"], metaNames["#g2s"] = "gsi2pk", "gsi2sk"
		metaValues[":true"], metaValues[":flags"] = b(true), s("flags")
	}
	return &dynamodb.TransactWriteItemsInput{TransactItems: []types.TransactWriteItem{
		{Put: &types.Put{
			TableName: &d.Table,
			Item: item{"pk": s("REPORT#" + f.ReportID), "sk": s("FLAG#" + f.InstallHash),
				"reason": s(f.Reason), "createdAt": created, "ttl": ttl},
			ConditionExpression: noFlag, ExpressionAttributeNames: names,
		}},
		{Put: &types.Put{
			TableName:           &d.Table,
			Item:                item{"pk": s("REPORT#" + f.ReportID), "sk": s("FLAGIP#" + f.IPHash), "ttl": ttl},
			ConditionExpression: noFlag, ExpressionAttributeNames: names,
		}},
		{Update: &types.Update{
			TableName:                 &d.Table,
			Key:                       reportKey(f.ReportID),
			UpdateExpression:          &update,
			ConditionExpression:       ptr("#fc = :seen AND attribute_not_exists(#h)"),
			ExpressionAttributeNames:  metaNames,
			ExpressionAttributeValues: metaValues,
		}},
	}}
}

// ---- counters ----------------------------------------------------------------

func (d *Dynamo) Incr(ctx context.Context, key string, limit int, expires time.Time) (int, bool, error) {
	out, err := d.DB.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                 &d.Table,
		Key:                       d.pk(key, "COUNT"),
		UpdateExpression:          ptr("SET #ttl = :ttl ADD #n :one"),
		ConditionExpression:       ptr("attribute_not_exists(#n) OR #n < :limit"),
		ExpressionAttributeNames:  map[string]string{"#ttl": "ttl", "#n": "n"},
		ExpressionAttributeValues: item{":ttl": n(expires.Unix()), ":one": n(1), ":limit": n(int64(limit))},
		ReturnValues:              types.ReturnValueUpdatedNew,
	})
	if isConditionFailed(err) {
		return limit, false, nil
	}
	if err != nil {
		return 0, false, unavailable(err)
	}
	count, _ := num(out.Attributes, "n")
	return int(count), true, nil
}

// ---- conditions ----------------------------------------------------------------

func (d *Dynamo) getCondition(ctx context.Context, sk string) (item, error) {
	out, err := d.DB.GetItem(ctx, &dynamodb.GetItemInput{TableName: &d.Table, Key: d.pk("CONDITIONS", sk)})
	if err != nil {
		return nil, unavailable(err)
	}
	if len(out.Item) == 0 {
		return nil, nil
	}
	return out.Item, nil
}

func (d *Dynamo) putCondition(ctx context.Context, it item) error {
	_, err := d.DB.PutItem(ctx, &dynamodb.PutItemInput{TableName: &d.Table, Item: it})
	return unavailable(err)
}

func (d *Dynamo) GetWeather(ctx context.Context) (*Weather, error) {
	it, err := d.getCondition(ctx, "WEATHER")
	if err != nil || it == nil {
		return nil, err
	}
	w := Weather{ObservedAt: when(it, "observedAt"), FetchedAt: when(it, "fetchedAt")}
	w.TemperatureC, _ = num(it, "temperatureC")
	w.ApparentTemperatureC, _ = num(it, "apparentTemperatureC")
	h, _ := num(it, "relativeHumidityPercent")
	w.RelativeHumidityPercent = int(h)
	if v, ok := num(it, "apparentTemperatureMaxTodayC"); ok {
		w.ApparentTemperatureMaxTodayC = &v
	}
	return &w, nil
}

func (d *Dynamo) PutWeather(ctx context.Context, w Weather) error {
	it := d.pk("CONDITIONS", "WEATHER")
	it["temperatureC"], it["apparentTemperatureC"] = nf(w.TemperatureC), nf(w.ApparentTemperatureC)
	it["relativeHumidityPercent"] = n(int64(w.RelativeHumidityPercent))
	if w.ApparentTemperatureMaxTodayC != nil {
		it["apparentTemperatureMaxTodayC"] = nf(*w.ApparentTemperatureMaxTodayC)
	}
	it["observedAt"], it["fetchedAt"] = s(httpx.FormatTime(w.ObservedAt)), s(httpx.FormatTime(w.FetchedAt))
	return d.putCondition(ctx, it)
}

func (d *Dynamo) GetNotices(ctx context.Context) (*Notices, error) {
	it, err := d.getCondition(ctx, "SMAT")
	if err != nil || it == nil {
		return nil, err
	}
	out := Notices{FetchedAt: when(it, "fetchedAt"), Items: []Notice{}}
	if l, ok := it["items"].(*types.AttributeValueMemberL); ok {
		for _, v := range l.Value {
			m, ok := v.(*types.AttributeValueMemberM)
			if !ok {
				continue
			}
			nt := Notice{
				ID: str(m.Value, "id"), Kind: str(m.Value, "kind"), Street: str(m.Value, "street"),
				Match: str(m.Value, "match"), StartedOn: str(m.Value, "startedOn"),
				PlannedEnd: str(m.Value, "plannedEnd"), Source: str(m.Value, "source"),
				FetchedAt: when(m.Value, "fetchedAt"), FountainIDs: []string{},
			}
			if ids, ok := m.Value["fountainIDs"].(*types.AttributeValueMemberL); ok {
				for _, id := range ids.Value {
					if sv, ok := id.(*types.AttributeValueMemberS); ok {
						nt.FountainIDs = append(nt.FountainIDs, sv.Value)
					}
				}
			}
			out.Items = append(out.Items, nt)
		}
	}
	return &out, nil
}

func (d *Dynamo) PutNotices(ctx context.Context, set Notices) error {
	items := make([]types.AttributeValue, len(set.Items))
	for i, nt := range set.Items {
		ids := make([]types.AttributeValue, len(nt.FountainIDs))
		for j, id := range nt.FountainIDs {
			ids[j] = s(id)
		}
		m := item{
			"id": s(nt.ID), "kind": s(nt.Kind), "street": s(nt.Street),
			"fountainIDs": &types.AttributeValueMemberL{Value: ids},
			"match":       s(nt.Match), "startedOn": s(nt.StartedOn), "source": s(nt.Source),
			"fetchedAt": s(httpx.FormatTime(nt.FetchedAt)),
		}
		if nt.PlannedEnd != "" {
			m["plannedEnd"] = s(nt.PlannedEnd)
		}
		items[i] = &types.AttributeValueMemberM{Value: m}
	}
	it := d.pk("CONDITIONS", "SMAT")
	it["fetchedAt"] = s(httpx.FormatTime(set.FetchedAt))
	it["items"] = &types.AttributeValueMemberL{Value: items}
	return d.putCondition(ctx, it)
}

func ptr[T any](v T) *T { return &v }
