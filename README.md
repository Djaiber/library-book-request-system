# Library Book Request System

A serverless application deployed on AWS that allows library users to request books to be added to the digital library catalog.

## Overview

This system provides a platform for library patrons to submit requests for new books to be added to the library's digital catalog. Built using AWS serverless technologies for scalability and cost efficiency.

## Branch Strategy

This repository follows a structured branching strategy:

| Branch    | Purpose                                                  |
|-----------|----------------------------------------------------------|
| `main`    | Production-ready code. Protected — requires PR review.  |
| `develop` | Integration branch for completed features. Default branch. |
| `feature/*` | Individual feature development branches.              |

### Workflow

1. Create a `feature/<feature-name>` branch off `develop`
2. Develop and test your changes
3. Open a Pull Request to merge into `develop`
4. After validation, `develop` is merged into `main` for production releases

## Getting Started

### Prerequisites

- Python 3.x
- Terraform
- AWS CLI configured with appropriate credentials

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature develop`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request targeting the `develop` branch
