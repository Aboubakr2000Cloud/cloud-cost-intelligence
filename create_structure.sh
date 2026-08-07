#!/bin/bash

mkdir -p terraform/modules/{vpc,rds,ecs,alb,security_groups,lambda,monitoring,frontend,ingestion}
mkdir -p terraform/backends
mkdir -p terraform/envs

mkdir -p api/templates

mkdir -p functions/{collector,anomaly_detector,data_seeder}

mkdir -p frontend/css
mkdir -p frontend/js

mkdir -p migrations
mkdir -p scripts

mkdir -p .github/workflows

touch terraform/{main.tf,variables.tf,outputs.tf,providers.tf,locals.tf,data.tf,iam.tf,secrets.tf}
touch terraform/backends/prod.hcl
touch terraform/envs/prod.tfvars

touch api/{app.py,requirements.txt,Dockerfile}
touch api/templates/index.html

touch functions/collector/app.py
touch functions/anomaly_detector/app.py
touch functions/data_seeder/app.py

touch frontend/index.html
touch frontend/css/style.css
touch frontend/js/dashboard.js

touch migrations/001_schema.sql

touch scripts/{build-functions.sh,seed-data.sh,smoke-test.sh,deploy-frontend.sh}

touch .github/workflows/{ci.yml,deploy.yml}

touch .dockerignore
touch .gitignore
touch README.md

echo "Project structure created successfully!"
