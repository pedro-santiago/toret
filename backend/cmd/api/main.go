// Command api is the Lambda behind the HTTP API (payload format 2.0).
package main

import (
	"context"
	"log/slog"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/ssm"

	"github.com/pedro-santiago/toret/backend/internal/api"
	"github.com/pedro-santiago/toret/backend/internal/catalogue"
	"github.com/pedro-santiago/toret/backend/internal/store"
)

// version is set at build time: -ldflags "-X main.version=1.0.0".
var version = "1.0.0"

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	table := os.Getenv("TABLE_NAME")
	if table == "" {
		log.Error("TABLE_NAME is not set")
		os.Exit(1)
	}
	cat, err := catalogue.Embedded()
	if err != nil {
		log.Error("catalogue", "err", err)
		os.Exit(1)
	}
	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		log.Error("aws config", "err", err)
		os.Exit(1)
	}
	param := os.Getenv("PEPPER_PARAM")
	if param == "" {
		param = "/toret/pepper"
	}
	parameters := ssm.NewFromConfig(cfg)

	h := api.New(api.Config{
		Store:     &store.Dynamo{DB: dynamodb.NewFromConfig(cfg), Table: table},
		Catalogue: cat,
		// Read once per cold start, on the first write (api.Handler keeps it).
		Pepper: func(ctx context.Context) ([]byte, error) {
			out, err := parameters.GetParameter(ctx, &ssm.GetParameterInput{Name: &param, WithDecryption: boolPtr(true)})
			if err != nil {
				return nil, err
			}
			return []byte(*out.Parameter.Value), nil
		},
		SMATEnabled: strings.EqualFold(os.Getenv("SMAT_ENABLED"), "true"),
		Version:     version,
		Logger:      log,
	})
	lambda.Start(h.Handle)
}

func boolPtr(b bool) *bool { return &b }
