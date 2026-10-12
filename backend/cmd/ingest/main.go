// Command ingest is the scheduled Lambda that fills the weather and SMAT caches.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"

	"github.com/pedro-santiago/toret/backend/internal/catalogue"
	"github.com/pedro-santiago/toret/backend/internal/ingest"
	"github.com/pedro-santiago/toret/backend/internal/smat"
	"github.com/pedro-santiago/toret/backend/internal/store"
	"github.com/pedro-santiago/toret/backend/internal/weather"
)

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
	r := &ingest.Runner{
		Store:       &store.Dynamo{DB: dynamodb.NewFromConfig(cfg), Table: table},
		Catalogue:   cat,
		Weather:     weather.Client{HTTP: &http.Client{Timeout: 15 * time.Second}},
		SMAT:        smat.Client{HTTP: &http.Client{Timeout: 40 * time.Second}},
		SMATEnabled: strings.EqualFold(os.Getenv("SMAT_ENABLED"), "true"),
		Now:         time.Now,
		Log:         log,
	}
	lambda.Start(r.Handle)
}
