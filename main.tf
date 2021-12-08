terraform {
  required_providers {
    vultr = {
      source = "vultr/vultr"
      version = "2.5.0"
    }
  }
}

# Configure the Vultr Provider
provider "vultr" {
  api_key = var.vultr_api
  rate_limit = 700
  retry_limit = 3
}

resource "vultr_ssh_key" "user" {
  count = length(var.ssh_keys)
  name = "tf-cosmos-ha-${count.index}"
  ssh_key = var.ssh_keys[count.index]
}

resource "random_string" "token_vpncloud" {
  length = 53 # log2 62^53 ~ 256
  special = false
}

resource "random_string" "token_croc" {
  length = 53
  special = false
}

data "local_file" "sentry_cloud_init" {
    filename = "${path.root}/ci-sentry.yaml"
}

resource "vultr_instance" "sentry" {
  count = var.sentry_count
  plan = "vhf-2c-2gb" # fast
  #plan = "vc2-1c-1gb" # cheapest
  region = element(var.sentry_regions, count.index)
  os_id = "477" # Debian 11
  label = "sentry-${count.index}-label"
  tag = "sentry-${count.index}-tag"
  hostname = "sentry-${count.index}.cluster"
  enable_ipv6 = true
  backups = "disabled" # costs $2.40
  ddos_protection = false # costs $10
  activation_email = false
  ssh_key_ids = vultr_ssh_key.user.*.id
  user_data = "${data.local_file.sentry_cloud_init.content}"
}

locals {
  vpn_c_args = "${join(" ", formatlist("-c %s", vultr_instance.sentry.*.main_ip))}"
  vpn_c_args_val = "${join(" ", formatlist("-c %s", vultr_instance.validator.*.main_ip))}"
}

resource "null_resource" "activate_sentry" {
  depends_on = [vultr_instance.sentry]
  count = var.sentry_count
  triggers = {
    ip0 = "${vultr_instance.sentry.0.main_ip}"
  }
  connection {
    host = "${element(vultr_instance.sentry.*.main_ip, count.index)}"
    password = "${element(vultr_instance.sentry.*.default_password, count.index)}"
  }
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "nohup vpncloud  --config /etc/vpncloud/ha.net --daemon --password '${random_string.token_vpncloud.result}' --ip 10.0.0.1${count.index} ${local.vpn_c_args} ${local.vpn_c_args_val}",
      "su -lc 'gaiad init tf-hackatom-sentry-${count.index}' cosmos",
      "su -lc 'gaiad tendermint show-node-id | croc send -c  ${random_string.token_croc.result}-${count.index}' cosmos &",
      "wget -O /tmp/testnet_genesis.json.gz https://github.com/cosmos/vega-test/raw/master/public-testnet/modified_genesis_public_testnet/genesis.json.gz",
      "gzip -d /tmp/testnet_genesis.json.gz",
      "mv /tmp/testnet_genesis.json /home/cosmos/.gaia/config/genesis.json",
      "chown cosmos:cosmos /home/cosmos/.gaia/config/genesis.json",
      "systemctl enable cosmovisor",
      "systemctl start cosmovisor",
    ]
  }
}

data "local_file" "validator_cloud_init" {
    filename = "${path.root}/ci-validator.yaml"
}

resource "vultr_instance" "validator" {
  count = 1
  plan = "vhf-2c-2gb" # fast
  #plan = "vc2-1c-1gb" # cheapest
  region = "sto" # stockholm
  os_id = "477" # Debian 11
  label = "val-${count.index}-label"
  tag = "val-${count.index}-tag"
  hostname = "val-${count.index}.cluster"
  enable_ipv6 = true
  backups = "disabled" # costs $2.40
  ddos_protection = false # costs $10
  activation_email = false
  ssh_key_ids = vultr_ssh_key.user.*.id
  user_data = "${data.local_file.validator_cloud_init.content}"
}

resource "null_resource" "add_sentry_ids" {
  depends_on = [null_resource.activate_sentry]
  triggers = {
    ip0 = "${vultr_instance.validator.0.main_ip}"
    sentry = "${vultr_instance.sentry.0.main_ip}"
  }
  count = var.sentry_count
  connection {
    host = "${element(vultr_instance.validator.*.main_ip, count.index)}"
    password = "${element(vultr_instance.validator.*.default_password, count.index)}"
  }
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "su -lc 'yes | croc --yes --stdout --overwrite ${random_string.token_croc.result}-${count.index} > /tmp/sentry-${count.index}.id' cosmos",
      <<-EOT
      grep '^persistent_peers = ".+"$' /home/cosmos/.gaia/config/config.toml && sed -i -E 's/(^persistent_peers = ".+)("$)/\1,'"$(cat /tmp/sentry-${count.index}.id | tr -d \\n)@10.0.0.1${count.index}:26656"'\2/' /home/cosmos/.gaia/config/config.toml
      EOT
      ,
      <<-EOT
      grep '^persistent_peers = ""$' /home/cosmos/.gaia/config/config.toml && sed -i -E 's/(^persistent_peers = ")("$)/\1'"$(cat /tmp/sentry-${count.index}.id | tr -d \\n)@10.0.0.1${count.index}:26656"'\2/' /home/cosmos/.gaia/config/config.toml
      EOT
      ,
    ]
  }
}
resource "null_resource" "activate_validator" {
  depends_on = [null_resource.add_sentry_ids]
  triggers = {
    ip0 = "${vultr_instance.validator.0.main_ip}"
  }
  count = 1
  connection {
    host = "${element(vultr_instance.validator.*.main_ip, count.index)}"
    password = "${element(vultr_instance.validator.*.default_password, count.index)}"
  }
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "echo ExecStart=/usr/local/bin/vpncloud --config /etc/vpncloud/ha.net --password '${random_string.token_vpncloud.result}' --ip 10.0.0.10${count.index} ${local.vpn_c_args} >> /etc/systemd/system/vpncloud.service",
      "systemctl daemon-reload",
      "systemctl start vpncloud",
      "wget -O /tmp/testnet_genesis.json.gz https://github.com/cosmos/vega-test/raw/master/public-testnet/modified_genesis_public_testnet/genesis.json.gz",
      "gzip -d /tmp/testnet_genesis.json.gz",
      "mv /tmp/testnet_genesis.json /home/cosmos/.gaia/config/genesis.json",
      "chown cosmos:cosmos /home/cosmos/.gaia/config/genesis.json",
      "systemctl enable cosmovisor",
      "ufw default deny outgoing",
      "systemctl start cosmovisor",
    ]
  }
}

output "sentry_ips" {
  value = vultr_instance.sentry.*.main_ip
}

output "val_ips" {
  value = vultr_instance.validator.*.main_ip
}
