# aws-python-lambda-layer
Complete AWS Lambda Function in Python with Layer for aws-xray-sdk depedency and cloudwatch alarm

# CI
Continuous Integration is run through GitHub actions in [ci.yml](./.github/workflows/ci.yml) on PR to `main` where we lint, test and plan out infrastructure resources. We add a PR comment to show the results of our Terraform efforts to plan our infrastructure.

# CD
Continuous Delivery is run through GitHub actions in [cd.yml](./.github/workflows/cd.yml) on push to `main` branch.