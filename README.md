# press-enter-validator

> Hackathom VI 2021 submission

Run a fully fledged production ready Cosmos validator/sentry model setup thanks to the power of IaC (Infrastructure as Code) and some linux sysadmin magic powder. Currently hardcoded for vega-testnet.

## Requirements

- Vultr account + API key
- Terraform

## Run

- to install the necessary terraform modules

```sh
terraform init
```

- to start this cluster... of sentries and validator

```sh
export TF_VARS_ssh_keys=["your_first_pubkey", "your_other_pubkey"]
TF_VARS_vultr_api="your_secret_vultr_api" terraform apply -auto-approve
```

- yes, it's that easy, the last couple lines will show the validator & sentry ips, which you can connect to to inspect, or leave as is.

## Finish

- to kill the started instances, if you were just testing

```sh
TF_VARS_vultr_api="your_secret_vultr_api" terraform destroy
```

