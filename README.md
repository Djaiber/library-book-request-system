# Library Book Request System

A serverless application deployed on AWS that allows library users to request books to be added to the digital library catalog.

## Overview

This system provides a platform for library patrons to submit requests for new books to be added to the library's digital catalog. Built using AWS serverless technologies for scalability and cost efficiency.

### Architecture

```
┌────────────┐       ┌──────────────────────┐       ┌──────────────────┐
│   Client   │──────▶│   API Gateway        │──────▶│ Producer Lambda  │
│ (HTTP POST)│       │ POST /requests       │       │ (Python 3.12)    │
└────────────┘       │ - Request validation │       │ - ISBN validation│
                     │ - CORS (OPTIONS)     │       │ - Build message  │
                     └──────────────────────┘       └────────┬─────────┘
                                                             │
                                                             ▼
                                                    ┌────────────────┐
                                                    │   SQS Queue    │
                                                    │ - Main queue   │
                                                    │ - Dead-letter  │
                                                    │   queue (DLQ)  │
                                                    └────────┬───────┘
                                                             │
                                                             ▼
                                                    ┌────────────────┐
                                                    │ Consumer Lambda│
                                                    │  (planned)     │
                                                    └────────┬───────┘
                                                             │
                                                             ▼
                                                    ┌────────────────┐
                                                    │   DynamoDB     │
                                                    │ BooksRequest   │
                                                    │ - requestId PK │
                                                    │ - StatusIndex  │
                                                    │   GSI          │
                                                    └────────────────┘
```

**Request flow:**

1. A client sends a `POST` request to API Gateway at `/requests`.
2. API Gateway validates the request body against a JSON schema and forwards it to the **Producer Lambda**.
3. The Producer Lambda validates the payload (required fields, ISBN format), generates a unique `requestId`, and publishes the message to an **SQS queue**.
4. A consumer (planned) reads from SQS and persists the record in a **DynamoDB** table.
5. Failed messages are retried and eventually routed to a **dead-letter queue** for inspection.

**AWS services used:**

| Service | Purpose |
|---|---|
| API Gateway | REST API with request validation and CORS |
| Lambda | Serverless compute (Python 3.12) |
| SQS | Asynchronous message queue with DLQ |
| DynamoDB | NoSQL storage with GSI and TTL |
| IAM | Least-privilege roles and policies |
| S3 | Terraform remote state backend |

## Setup Instructions

### Prerequisites

- **Python** 3.12+
- **Terraform** ≥ 1.5.0
- **AWS CLI** v2 configured with appropriate credentials
- **jq** (used by the bootstrap script)

### 1. Clone the Repository

```bash
git clone https://github.com/Djaiber/library-book-request-system.git
cd library-book-request-system
```

### 2. Create the `.env` File

Create a `.env` file in the project root with the following variables:

```bash
ENV_TF_STATE_BUCKET=<your-unique-s3-bucket-name>
TF_STATE_REGION=us-east-2
```

### 3. Bootstrap the Terraform S3 Backend

The bootstrap script creates an S3 bucket for Terraform state with versioning, encryption, public-access blocking, and TLS enforcement:

```bash
# Create buckets for both environments
./terraform/config/pre-setup.sh

# Or create for a specific environment
./terraform/config/pre-setup.sh prod
./terraform/config/pre-setup.sh qa
```

### 4. Initialize Terraform

```bash
cd terraform

# Initialize with the S3 backend
# Source your .env first, or replace $ENV_TF_STATE_BUCKET with your bucket name
source ../.env
terraform init -backend-config="bucket=$ENV_TF_STATE_BUCKET" \
               -backend-config=config/backend.conf

# Validate the configuration
terraform validate
```

## Local Development Guide

### Python Environment

```bash
# Create and activate a virtual environment
python3 -m venv venv
source venv/bin/activate    # Linux/macOS
# venv\Scripts\activate     # Windows

# Install dependencies
pip install -r src/producer/requirements.txt

# Install test dependencies
pip install pytest moto boto3
```

### Running Tests

```bash
# Run the full test suite
python -m pytest tests/ -v

# Run a specific test file
python -m pytest tests/test_producer.py -v
```

### Terraform Validation

```bash
cd terraform

# Check formatting
terraform fmt -check -diff .

# Validate configuration (without requiring AWS credentials)
terraform init -backend=false
terraform validate

# Preview changes
terraform plan -var-file=config/qa.tfvars
```

### Branch Strategy

| Branch | Purpose |
|---|---|
| `main` | Production-ready code. Protected — requires PR review. |
| `develop` | Integration branch for completed features. Default branch. |
| `feature/*` | Individual feature development branches. |

**Workflow:**

1. Create a `feature/<feature-name>` branch off `develop`
2. Develop and test your changes
3. Open a Pull Request to merge into `develop`
4. After validation, `develop` is merged into `main` for production releases

## API Documentation

### `POST /requests`

Submit a new book request.

**Endpoint:**

```
https://<api-id>.execute-api.us-east-2.amazonaws.com/<environment>/requests
```

**Headers:**

| Header | Value |
|---|---|
| `Content-Type` | `application/json` |

**Request body:**

| Field | Type | Required | Description |
|---|---|---|---|
| `title` | string | Yes | Title of the requested book |
| `author` | string | Yes | Author of the book |
| `isbn` | string | Yes | ISBN-10 or ISBN-13 |
| `requesterName` | string | No | Name of the person requesting |
| `notes` | string | No | Additional notes or comments |

**Example request:**

Replace `<api-id>` with the value from `terraform output api_gateway_rest_api_id` and the stage with your target environment.

```bash
curl -X POST \
  https://<api-id>.execute-api.us-east-2.amazonaws.com/<environment>/requests \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Clean Code",
    "author": "Robert C. Martin",
    "isbn": "9780132350884",
    "requesterName": "Jane Doe",
    "notes": "Needed for the software engineering book club"
  }'
```

**Success response (`200`):**

```json
{
  "message": "Book request submitted successfully.",
  "requestId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**Validation error response (`400`):**

```json
{
  "message": "Validation failed.",
  "errors": [
    "Missing or empty required field: title",
    "Invalid ISBN format. Must be a valid ISBN-10 or ISBN-13."
  ]
}
```

**Server error response (`500`):**

```json
{
  "message": "Failed to process request. Please try again later."
}
```

### `OPTIONS /requests`

CORS preflight endpoint. Returns allowed headers, methods, and origins automatically.

## Deployment Process

### 1. Plan Changes

Review what Terraform will create or modify:

```bash
cd terraform
terraform plan -var-file=config/qa.tfvars
```

### 2. Apply to QA

```bash
terraform apply -var-file=config/qa.tfvars
```

### 3. Apply to Production

```bash
terraform apply -var-file=config/prod.tfvars
```

### 4. Review Outputs

After a successful apply, Terraform prints key resource identifiers:

```bash
terraform output
```

Key outputs include:

| Output | Description |
|---|---|
| `api_gateway_invoke_url` | Base URL of the API Gateway stage |
| `api_gateway_rest_api_id` | REST API identifier |
| `api_gateway_stage_name` | Deployed stage name (`qa` or `prod`) |
| `book_request_queue_url` | SQS queue URL |
| `book_request_queue_arn` | SQS queue ARN |
| `book_request_dlq_url` | Dead-letter queue URL |
| `lambda_execution_role_arn` | IAM role ARN used by Lambda functions |

### Destroying Resources

To tear down all resources for an environment:

```bash
terraform destroy -var-file=config/qa.tfvars
```

## Environment Variables Reference

### Terraform Variables

Defined in `terraform/variables.tf` and overridden per environment via `terraform/config/*.tfvars`.

| Variable | Type | Default | Description |
|---|---|---|---|
| `environment` | string | — (required) | Deployment environment (`dev`, `qa`, or `prod`) |
| `region` | string | `us-east-2` | AWS region for resource deployment |
| `project_name` | string | `library-book-request` | Project name used in resource naming |
| `tags` | map(string) | `{}` | Additional tags applied to all resources |
| `lambda_runtime` | string | `python3.12` | Lambda function runtime |
| `lambda_memory_size` | number | `128` | Lambda memory allocation (MB) |
| `lambda_timeout` | number | `30` | Lambda timeout (seconds) |
| `lambda_log_retention_days` | number | `14` | CloudWatch log retention (days) |

### Lambda Runtime Variables

Set via Terraform on the Lambda function configuration.

| Variable | Description |
|---|---|
| `SQS_QUEUE_URL` | URL of the SQS queue the producer publishes to |

### Bootstrap Script Variables (`.env`)

Used by `terraform/config/pre-setup.sh` to create the S3 state backend.

| Variable | Description |
|---|---|
| `ENV_TF_STATE_BUCKET` | Globally unique S3 bucket name for Terraform state |
| `TF_STATE_REGION` | AWS region for the state bucket (default `us-east-2`) |

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature develop`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request targeting the `develop` branch
