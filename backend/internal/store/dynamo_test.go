package store

import (
	"context"
	"errors"
	"reflect"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/smithy-go"
)

// stub records every request and answers from canned values.
type stub struct {
	gets    []*dynamodb.GetItemInput
	puts    []*dynamodb.PutItemInput
	deletes []*dynamodb.DeleteItemInput
	updates []*dynamodb.UpdateItemInput
	queries []*dynamodb.QueryInput
	txs     []*dynamodb.TransactWriteItemsInput

	getOut    func(in *dynamodb.GetItemInput) (*dynamodb.GetItemOutput, error)
	putErr    error
	deleteErr error
	updateOut *dynamodb.UpdateItemOutput
	updateErr error
	queryOut  func(in *dynamodb.QueryInput, call int) (*dynamodb.QueryOutput, error)
	txErr     func(call int) error
}

func (s *stub) GetItem(_ context.Context, in *dynamodb.GetItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
	s.gets = append(s.gets, in)
	if s.getOut != nil {
		return s.getOut(in)
	}
	return &dynamodb.GetItemOutput{}, nil
}
func (s *stub) PutItem(_ context.Context, in *dynamodb.PutItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
	s.puts = append(s.puts, in)
	return &dynamodb.PutItemOutput{}, s.putErr
}
func (s *stub) DeleteItem(_ context.Context, in *dynamodb.DeleteItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error) {
	s.deletes = append(s.deletes, in)
	return &dynamodb.DeleteItemOutput{}, s.deleteErr
}
func (s *stub) UpdateItem(_ context.Context, in *dynamodb.UpdateItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
	s.updates = append(s.updates, in)
	if s.updateOut == nil {
		return &dynamodb.UpdateItemOutput{}, s.updateErr
	}
	return s.updateOut, s.updateErr
}
func (s *stub) Query(_ context.Context, in *dynamodb.QueryInput, _ ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
	s.queries = append(s.queries, in)
	if s.queryOut != nil {
		return s.queryOut(in, len(s.queries))
	}
	return &dynamodb.QueryOutput{}, nil
}
func (s *stub) TransactWriteItems(_ context.Context, in *dynamodb.TransactWriteItemsInput, _ ...func(*dynamodb.Options)) (*dynamodb.TransactWriteItemsOutput, error) {
	s.txs = append(s.txs, in)
	if s.txErr != nil {
		return &dynamodb.TransactWriteItemsOutput{}, s.txErr(len(s.txs))
	}
	return &dynamodb.TransactWriteItemsOutput{}, nil
}

func newDynamo() (*Dynamo, *stub) {
	s := &stub{}
	return &Dynamo{DB: s, Table: "toret-test"}, s
}

var (
	ctx   = context.Background()
	t0    = time.Date(2026, 10, 12, 9, 41, 0, 0, time.UTC)
	five  = 5
	rep   = Record{ID: "7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10", FountainID: "421310659", State: "running", Rating: &five, Tags: []string{"cold", "clean"}, Note: "", Date: t0, CreatedAt: t0.Add(time.Minute), Author: "Visitante E95596", InstallHash: "abc"}
	cause = &smithyErr{code: "ConditionalCheckFailedException"}
)

type smithyErr struct{ code string }

func (e *smithyErr) Error() string                 { return e.code }
func (e *smithyErr) ErrorCode() string             { return e.code }
func (e *smithyErr) ErrorMessage() string          { return e.code }
func (e *smithyErr) ErrorFault() smithy.ErrorFault { return smithy.FaultClient }

func sv(v string) types.AttributeValue { return &types.AttributeValueMemberS{Value: v} }
func nv(v string) types.AttributeValue { return &types.AttributeValueMemberN{Value: v} }

func str1(t *testing.T, it map[string]types.AttributeValue, k string) string {
	t.Helper()
	v, ok := it[k].(*types.AttributeValueMemberS)
	if !ok {
		t.Fatalf("attribute %q is %T, want S", k, it[k])
	}
	return v.Value
}

func num1(t *testing.T, it map[string]types.AttributeValue, k string) string {
	t.Helper()
	v, ok := it[k].(*types.AttributeValueMemberN)
	if !ok {
		t.Fatalf("attribute %q is %T, want N", k, it[k])
	}
	return v.Value
}

// reserved checks that every expression refers to attributes only through
// #placeholders and :values: strip them and the DynamoDB keywords and nothing
// may remain.
func noBareNames(t *testing.T, exprs ...*string) {
	t.Helper()
	word := regexp.MustCompile(`[A-Za-z_][A-Za-z_0-9]*`)
	allowed := map[string]bool{"SET": true, "ADD": true, "REMOVE": true, "AND": true, "OR": true, "attribute_not_exists": true, "attribute_exists": true}
	for _, e := range exprs {
		if e == nil {
			continue
		}
		clean := regexp.MustCompile(`[#:][A-Za-z0-9_]+`).ReplaceAllString(*e, " ")
		for _, w := range word.FindAllString(clean, -1) {
			if !allowed[w] {
				t.Errorf("expression %q uses %q without a placeholder", *e, w)
			}
		}
	}
}

func TestPutReportShape(t *testing.T) {
	d, st := newDynamo()
	created, err := d.PutReport(ctx, rep)
	if err != nil || !created {
		t.Fatal(created, err)
	}
	in := st.puts[0]
	if *in.TableName != "toret-test" || *in.ConditionExpression != "attribute_not_exists(#pk)" || !reflect.DeepEqual(in.ExpressionAttributeNames, map[string]string{"#pk": "pk"}) {
		t.Errorf("put = %+v", in)
	}
	noBareNames(t, in.ConditionExpression)
	it := in.Item
	key := "2026-10-12T09:41:00Z#7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10"
	for k, want := range map[string]string{
		"pk": "REPORT#7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10", "sk": "META", "id": rep.ID, "fountainID": "421310659", "state": "running",
		"note": "", "date": "2026-10-12T09:41:00Z", "createdAt": "2026-10-12T09:42:00Z", "author": "Visitante E95596", "installHash": "abc",
		"dateKey": key, "fountainKey": "FOUNTAIN#421310659", "gsi1pk": "FEED", "gsi1sk": key, "gsi2pk": "FOUNTAIN#421310659", "gsi2sk": key,
	} {
		if got := str1(t, it, k); got != want {
			t.Errorf("%s = %q, want %q", k, got, want)
		}
	}
	// ttl is the report's date plus 30 days, not the time of the write.
	if got, want := num1(t, it, "ttl"), "1794390060"; got != want {
		t.Errorf("ttl = %s, want %s (date + 30 days)", got, want)
	}
	if num1(t, it, "rating") != "5" || num1(t, it, "flagCount") != "0" {
		t.Errorf("numbers: %v", it)
	}
	if l := it["tags"].(*types.AttributeValueMemberL); len(l.Value) != 2 {
		t.Errorf("tags = %v", l)
	}
	if _, has := it["hidden"]; has {
		t.Error("a new report is not hidden")
	}

	// Without a rating there is no rating attribute.
	r := rep
	r.Rating = nil
	r.Tags = nil
	d.PutReport(ctx, r)
	if _, has := st.puts[1].Item["rating"]; has {
		t.Error("rating must be absent when none")
	}
	if l := st.puts[1].Item["tags"].(*types.AttributeValueMemberL); l.Value == nil && len(l.Value) != 0 {
		t.Error("tags must be a list")
	}

	// A taken id is (false, nil), not an error.
	st.putErr = &types.ConditionalCheckFailedException{}
	if created, err := d.PutReport(ctx, rep); created || err != nil {
		t.Errorf("taken: %v %v", created, err)
	}
	st.putErr = &smithyErr{"ProvisionedThroughputExceededException"}
	if _, err := d.PutReport(ctx, rep); !errors.Is(err, ErrUnavailable) {
		t.Errorf("throttled: %v", err)
	}
}

func TestMarshalRoundTrip(t *testing.T) {
	r := rep
	r.FlagCount = 2
	got := unmarshalReport(marshalReport(r))
	if !reflect.DeepEqual(got, r) {
		t.Errorf("round trip\n got %+v\nwant %+v", got, r)
	}
	r.Rating, r.Tags = nil, nil
	got = unmarshalReport(marshalReport(r))
	if got.Rating != nil || got.Tags == nil || len(got.Tags) != 0 {
		t.Errorf("no rating / no tags: %+v", got)
	}
	hidden := marshalReport(rep)
	hidden["hidden"], hidden["hiddenBy"], hidden["reviewed"] = &types.AttributeValueMemberBOOL{Value: true}, sv("flags"), &types.AttributeValueMemberBOOL{Value: true}
	if g := unmarshalReport(hidden); !g.Hidden || g.HiddenBy != "flags" || !g.Reviewed {
		t.Errorf("hidden fields: %+v", g)
	}
}

func TestGetReportIsStronglyConsistent(t *testing.T) {
	d, st := newDynamo()
	st.getOut = func(in *dynamodb.GetItemInput) (*dynamodb.GetItemOutput, error) {
		return &dynamodb.GetItemOutput{Item: marshalReport(rep)}, nil
	}
	r, err := d.GetReport(ctx, rep.ID)
	if err != nil || r == nil || r.ID != rep.ID {
		t.Fatal(r, err)
	}
	in := st.gets[0]
	if in.ConsistentRead == nil || !*in.ConsistentRead || str1(t, in.Key, "pk") != "REPORT#"+rep.ID || str1(t, in.Key, "sk") != "META" {
		t.Errorf("get = %+v", in)
	}
	st.getOut = nil
	if r, err := d.GetReport(ctx, "X"); r != nil || err != nil {
		t.Errorf("missing: %v %v", r, err)
	}
}

func TestIncrShape(t *testing.T) {
	d, st := newDynamo()
	st.updateOut = &dynamodb.UpdateItemOutput{Attributes: map[string]types.AttributeValue{"n": nv("3")}}
	exp := time.Date(2026, 10, 12, 12, 0, 0, 0, time.UTC)
	count, ok, err := d.Incr(ctx, "RL#INSTALL#abc#493000", 40, exp)
	if count != 3 || !ok || err != nil {
		t.Fatal(count, ok, err)
	}
	in := st.updates[0]
	if str1(t, in.Key, "pk") != "RL#INSTALL#abc#493000" || str1(t, in.Key, "sk") != "COUNT" {
		t.Errorf("key = %v", in.Key)
	}
	if *in.UpdateExpression != "SET #ttl = :ttl ADD #n :one" || *in.ConditionExpression != "attribute_not_exists(#n) OR #n < :limit" {
		t.Errorf("expressions: %q / %q", *in.UpdateExpression, *in.ConditionExpression)
	}
	noBareNames(t, in.UpdateExpression, in.ConditionExpression)
	if !reflect.DeepEqual(in.ExpressionAttributeNames, map[string]string{"#ttl": "ttl", "#n": "n"}) {
		t.Errorf("names = %v", in.ExpressionAttributeNames)
	}
	if num1(t, in.ExpressionAttributeValues, ":limit") != "40" || num1(t, in.ExpressionAttributeValues, ":one") != "1" || num1(t, in.ExpressionAttributeValues, ":ttl") != "1791806400" {
		t.Errorf("values = %v", in.ExpressionAttributeValues)
	}
	if in.ReturnValues != types.ReturnValueUpdatedNew {
		t.Errorf("return values = %v", in.ReturnValues)
	}
	st.updateErr = &types.ConditionalCheckFailedException{}
	if count, ok, err := d.Incr(ctx, "k", 40, exp); count != 40 || ok || err != nil {
		t.Errorf("full: %d %v %v", count, ok, err)
	}
	st.updateErr = &smithyErr{"ThrottlingException"}
	if _, _, err := d.Incr(ctx, "k", 40, exp); !errors.Is(err, ErrUnavailable) {
		t.Errorf("throttled: %v", err)
	}
	st.updateErr = errors.New("connection reset")
	if _, _, err := d.Incr(ctx, "k", 40, exp); !errors.Is(err, ErrUnavailable) {
		t.Errorf("network: %v", err)
	}
	st.updateErr = &smithyErr{"ValidationException"}
	if _, _, err := d.Incr(ctx, "k", 40, exp); err == nil || errors.Is(err, ErrUnavailable) {
		t.Errorf("a bug must not look retryable: %v", err)
	}
}

func TestDeleteShape(t *testing.T) {
	d, st := newDynamo()
	if out, err := d.DeleteReport(ctx, rep.ID, "abc"); out != Deleted || err != nil {
		t.Fatal(out, err)
	}
	in := st.deletes[0]
	if *in.ConditionExpression != "#owner = :owner" || in.ExpressionAttributeNames["#owner"] != "installHash" ||
		str1(t, in.ExpressionAttributeValues, ":owner") != "abc" || in.ReturnValuesOnConditionCheckFailure != types.ReturnValuesOnConditionCheckFailureAllOld {
		t.Errorf("delete = %+v", in)
	}
	noBareNames(t, in.ConditionExpression)
	// The condition fails for a missing item and for someone else's; ALL_OLD
	// tells them apart.
	st.deleteErr = &types.ConditionalCheckFailedException{}
	if out, err := d.DeleteReport(ctx, rep.ID, "abc"); out != NotFound || err != nil {
		t.Errorf("missing: %v %v", out, err)
	}
	st.deleteErr = &types.ConditionalCheckFailedException{Item: marshalReport(rep)}
	if out, err := d.DeleteReport(ctx, rep.ID, "other"); out != NotOwner || err != nil {
		t.Errorf("not owner: %v %v", out, err)
	}
}

func TestQueryShape(t *testing.T) {
	d, st := newDynamo()
	// Two pages of one item each for a limit of 2: the second asks for one more.
	st.queryOut = func(in *dynamodb.QueryInput, call int) (*dynamodb.QueryOutput, error) {
		out := &dynamodb.QueryOutput{Items: []map[string]types.AttributeValue{marshalReport(rep)}}
		if call == 1 {
			out.LastEvaluatedKey = map[string]types.AttributeValue{"pk": sv("x")}
		}
		return out, nil
	}
	cutoff := time.Date(2026, 9, 12, 12, 0, 0, 0, time.UTC)
	got, err := d.Feed(ctx, cutoff, 2)
	if err != nil || len(got) != 2 {
		t.Fatal(len(got), err)
	}
	q := st.queries[0]
	if *q.IndexName != "gsi1" || *q.KeyConditionExpression != "#p = :p AND #s > :c" || *q.ScanIndexForward || *q.Limit != 2 {
		t.Errorf("query = %+v", q)
	}
	noBareNames(t, q.KeyConditionExpression)
	if q.ExpressionAttributeNames["#p"] != "gsi1pk" || q.ExpressionAttributeNames["#s"] != "gsi1sk" ||
		str1(t, q.ExpressionAttributeValues, ":p") != "FEED" || str1(t, q.ExpressionAttributeValues, ":c") != "2026-09-12T12:00:00Z#" {
		t.Errorf("query values: %v %v", q.ExpressionAttributeNames, q.ExpressionAttributeValues)
	}
	if q.FilterExpression != nil {
		t.Error("a filter after the limit would return short pages; the indexes are sparse instead")
	}
	if q2 := st.queries[1]; *q2.Limit != 1 || q2.ExclusiveStartKey == nil {
		t.Errorf("second page = %+v", q2)
	}

	st.queries = nil
	st.queryOut = nil
	if _, err := d.Fountain(ctx, "421310659", cutoff, 40); err != nil {
		t.Fatal(err)
	}
	q = st.queries[0]
	if *q.IndexName != "gsi2" || q.ExpressionAttributeNames["#p"] != "gsi2pk" || str1(t, q.ExpressionAttributeValues, ":p") != "FOUNTAIN#421310659" {
		t.Errorf("fountain query = %+v", q)
	}
}

func metaWith(count string, extra map[string]types.AttributeValue) func(in *dynamodb.GetItemInput) (*dynamodb.GetItemOutput, error) {
	return func(*dynamodb.GetItemInput) (*dynamodb.GetItemOutput, error) {
		it := marshalReport(rep)
		it["flagCount"] = nv(count)
		for k, v := range extra {
			it[k] = v
		}
		return &dynamodb.GetItemOutput{Item: it}, nil
	}
}

func flagReq() FlagRequest {
	return FlagRequest{ReportID: rep.ID, InstallHash: "flagger", IPHash: "iphash", Reason: "spam", Now: t0.Add(time.Hour)}
}

func TestFlagTransactionShape(t *testing.T) {
	d, st := newDynamo()
	st.getOut = metaWith("1", nil)
	out, err := d.Flag(ctx, flagReq())
	if err != nil || out != FlagCounted {
		t.Fatal(out, err)
	}
	items := st.txs[0].TransactItems
	if len(items) != 3 || items[0].Put == nil || items[1].Put == nil || items[2].Update == nil {
		t.Fatalf("transaction = %+v", items)
	}
	ttl := "1794390060" // the report's date plus 30 days, like the report
	a, b, u := items[0].Put, items[1].Put, items[2].Update
	if str1(t, a.Item, "pk") != "REPORT#"+rep.ID || str1(t, a.Item, "sk") != "FLAG#flagger" || str1(t, a.Item, "reason") != "spam" ||
		str1(t, a.Item, "createdAt") != "2026-10-12T10:41:00Z" || num1(t, a.Item, "ttl") != ttl {
		t.Errorf("flag item = %v", a.Item)
	}
	if str1(t, b.Item, "sk") != "FLAGIP#iphash" || num1(t, b.Item, "ttl") != ttl {
		t.Errorf("ip item = %v", b.Item)
	}
	for _, p := range []*types.Put{a, b} {
		if *p.ConditionExpression != "attribute_not_exists(#pk)" || p.ExpressionAttributeNames["#pk"] != "pk" {
			t.Errorf("put condition = %q %v", *p.ConditionExpression, p.ExpressionAttributeNames)
		}
		noBareNames(t, p.ConditionExpression)
	}
	if *u.UpdateExpression != "ADD #fc :one" || *u.ConditionExpression != "#fc = :seen AND attribute_not_exists(#h)" ||
		num1(t, u.ExpressionAttributeValues, ":seen") != "1" || num1(t, u.ExpressionAttributeValues, ":one") != "1" ||
		u.ExpressionAttributeNames["#fc"] != "flagCount" || u.ExpressionAttributeNames["#h"] != "hidden" ||
		str1(t, u.Key, "pk") != "REPORT#"+rep.ID || str1(t, u.Key, "sk") != "META" {
		t.Errorf("update = %+v", u)
	}
	noBareNames(t, u.UpdateExpression, u.ConditionExpression)
	if g := st.gets[0].ConsistentRead; g == nil || !*g {
		t.Error("the META read before a flag must be strongly consistent")
	}
}

func TestFlagThirdFlaggerHides(t *testing.T) {
	d, st := newDynamo()
	st.getOut = metaWith("2", nil)
	out, err := d.Flag(ctx, flagReq())
	if err != nil || out != FlagCountedAndHidden {
		t.Fatal(out, err)
	}
	u := st.txs[0].TransactItems[2].Update
	if *u.UpdateExpression != "SET #h = :true, #hb = :flags ADD #fc :one REMOVE #g1p, #g1s, #g2p, #g2s" {
		t.Errorf("update expression = %q", *u.UpdateExpression)
	}
	noBareNames(t, u.UpdateExpression)
	wantNames := map[string]string{"#fc": "flagCount", "#h": "hidden", "#hb": "hiddenBy", "#g1p": "gsi1pk", "#g1s": "gsi1sk", "#g2p": "gsi2pk", "#g2s": "gsi2sk"}
	if !reflect.DeepEqual(u.ExpressionAttributeNames, wantNames) {
		t.Errorf("names = %v", u.ExpressionAttributeNames)
	}
	if v := u.ExpressionAttributeValues[":true"].(*types.AttributeValueMemberBOOL); !v.Value || str1(t, u.ExpressionAttributeValues, ":flags") != "flags" || num1(t, u.ExpressionAttributeValues, ":seen") != "2" {
		t.Errorf("values = %v", u.ExpressionAttributeValues)
	}

	// A reviewed report is never auto-hidden again: plain increment.
	st.txs = nil
	st.getOut = metaWith("2", map[string]types.AttributeValue{"reviewed": &types.AttributeValueMemberBOOL{Value: true}})
	if out, _ := d.Flag(ctx, flagReq()); out != FlagCounted || *st.txs[0].TransactItems[2].Update.UpdateExpression != "ADD #fc :one" {
		t.Errorf("reviewed: %v %q", out, *st.txs[0].TransactItems[2].Update.UpdateExpression)
	}
}

func TestFlagIgnoredCases(t *testing.T) {
	d, st := newDynamo()
	for name, get := range map[string]func(*dynamodb.GetItemInput) (*dynamodb.GetItemOutput, error){
		"missing": func(*dynamodb.GetItemInput) (*dynamodb.GetItemOutput, error) { return &dynamodb.GetItemOutput{}, nil },
		"hidden":  metaWith("1", map[string]types.AttributeValue{"hidden": &types.AttributeValueMemberBOOL{Value: true}}),
		"owner":   metaWith("1", map[string]types.AttributeValue{"installHash": sv("flagger")}),
	} {
		st.getOut = get
		if out, err := d.Flag(ctx, flagReq()); out != FlagIgnored || err != nil {
			t.Errorf("%s: %v %v", name, out, err)
		}
	}
	if len(st.txs) != 0 {
		t.Error("an ignored flag must not write")
	}
}

func cancelled(codes ...string) error {
	var reasons []types.CancellationReason
	for _, c := range codes {
		c := c
		reasons = append(reasons, types.CancellationReason{Code: &c})
	}
	return &types.TransactionCanceledException{CancellationReasons: reasons}
}

func TestFlagCancellations(t *testing.T) {
	d, st := newDynamo()
	st.getOut = metaWith("0", nil)

	// A flag item already exists (this install, or this address): 204 upstream.
	for _, codes := range [][]string{{"ConditionalCheckFailed", "None", "None"}, {"None", "ConditionalCheckFailed", "None"}} {
		st.txErr = func(int) error { return cancelled(codes...) }
		if out, err := d.Flag(ctx, flagReq()); out != FlagDuplicate || err != nil {
			t.Errorf("%v: %v %v", codes, out, err)
		}
	}

	// flagCount moved: read again and retry; the second attempt lands.
	st.txs = nil
	st.gets = nil
	st.txErr = func(call int) error {
		if call == 1 {
			return cancelled("None", "None", "ConditionalCheckFailed")
		}
		return nil
	}
	if out, err := d.Flag(ctx, flagReq()); out != FlagCounted || err != nil || len(st.txs) != 2 || len(st.gets) != 2 {
		t.Errorf("retry: %v %v, %d transactions, %d reads", out, err, len(st.txs), len(st.gets))
	}

	// Up to three attempts, then unavailable.
	st.txs = nil
	st.txErr = func(int) error { return cancelled("None", "None", "TransactionConflict") }
	if _, err := d.Flag(ctx, flagReq()); !errors.Is(err, ErrUnavailable) || len(st.txs) != 3 {
		t.Errorf("exhausted: %v after %d attempts", err, len(st.txs))
	}

	// Anything else is not retried.
	st.txs = nil
	st.txErr = func(int) error { return &smithyErr{"ValidationException"} }
	if _, err := d.Flag(ctx, flagReq()); err == nil || len(st.txs) != 1 {
		t.Errorf("validation error: %v after %d attempts", err, len(st.txs))
	}
}

func TestBanned(t *testing.T) {
	d, st := newDynamo()
	if b, err := d.Banned(ctx, "abc", "def"); b || err != nil {
		t.Fatal(b, err)
	}
	if len(st.gets) != 2 || str1(t, st.gets[0].Key, "pk") != "BAN#abc" || str1(t, st.gets[0].Key, "sk") != "BAN" ||
		str1(t, st.gets[1].Key, "pk") != "BANIP#def" || str1(t, st.gets[1].Key, "sk") != "BAN" {
		t.Errorf("keys = %v", st.gets)
	}
	// Only the address is banned: the second lookup finds it.
	st.getOut = func(in *dynamodb.GetItemInput) (*dynamodb.GetItemOutput, error) {
		if str1(t, in.Key, "pk") == "BANIP#def" {
			return &dynamodb.GetItemOutput{Item: map[string]types.AttributeValue{"pk": sv("BANIP#def")}}, nil
		}
		return &dynamodb.GetItemOutput{}, nil
	}
	if b, _ := d.Banned(ctx, "abc", "def"); !b {
		t.Error("a banned address must be banned")
	}
	if b, _ := d.Banned(ctx, "abc", "other"); b {
		t.Error("another address must not be banned")
	}
	// A banned install stops at the first lookup.
	st.gets = nil
	st.getOut = func(*dynamodb.GetItemInput) (*dynamodb.GetItemOutput, error) {
		return &dynamodb.GetItemOutput{Item: map[string]types.AttributeValue{"pk": sv("BAN#abc")}}, nil
	}
	if b, _ := d.Banned(ctx, "abc", "def"); !b || len(st.gets) != 1 {
		t.Errorf("banned install: %v after %d lookups", b, len(st.gets))
	}
}

func TestConditionsRoundTrip(t *testing.T) {
	d, st := newDynamo()
	var stored map[string]types.AttributeValue
	st.getOut = func(in *dynamodb.GetItemInput) (*dynamodb.GetItemOutput, error) {
		return &dynamodb.GetItemOutput{Item: stored}, nil
	}
	max := 29.5
	w := Weather{TemperatureC: 24.1, ApparentTemperatureC: 26.3, RelativeHumidityPercent: 48, ApparentTemperatureMaxTodayC: &max, ObservedAt: t0, FetchedAt: t0.Add(time.Minute)}
	if err := d.PutWeather(ctx, w); err != nil {
		t.Fatal(err)
	}
	stored = st.puts[0].Item
	if str1(t, stored, "pk") != "CONDITIONS" || str1(t, stored, "sk") != "WEATHER" {
		t.Errorf("weather key: %v", stored)
	}
	got, err := d.GetWeather(ctx)
	if err != nil || !reflect.DeepEqual(*got, w) {
		t.Errorf("weather round trip: %+v %v", got, err)
	}
	w.ApparentTemperatureMaxTodayC = nil
	d.PutWeather(ctx, w)
	if _, has := st.puts[1].Item["apparentTemperatureMaxTodayC"]; has {
		t.Error("absent daily max must not be written")
	}

	set := Notices{FetchedAt: t0, Items: []Notice{
		{ID: "a1b2c3d4e5f6", Kind: "waterWorks", Street: "Via Po", FountainIDs: []string{"1", "2"}, Match: "street", StartedOn: "2026-10-05", PlannedEnd: "2026-10-23", Source: "SMAT S.p.A., Mappa Cantieri", FetchedAt: t0},
		{ID: "b1b2c3d4e5f6", Kind: "fountainWorks", Street: "Via Roma", FountainIDs: []string{}, Match: "street", StartedOn: "2026-10-01", Source: "SMAT S.p.A., Mappa Cantieri", FetchedAt: t0},
	}}
	if err := d.PutNotices(ctx, set); err != nil {
		t.Fatal(err)
	}
	stored = st.puts[2].Item
	if str1(t, stored, "sk") != "SMAT" {
		t.Errorf("smat key: %v", stored)
	}
	gotN, err := d.GetNotices(ctx)
	if err != nil || !reflect.DeepEqual(*gotN, set) {
		t.Errorf("notices round trip:\n got %+v\nwant %+v (%v)", gotN, set, err)
	}
	if strings.Contains(strings.ToLower(str1(t, stored, "sk")), "status") {
		t.Error("no status")
	}
	stored = nil
	if g, err := d.GetNotices(ctx); g != nil || err != nil {
		t.Errorf("empty: %v %v", g, err)
	}
}
