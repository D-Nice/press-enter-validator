variable "vultr_api" {
  type = string
}

variable "ssh_keys" {
  type = list(string)
}

variable "sentry_count" {
  type = number
  default = 1
}

variable "sentry_regions" {
  type = list(string)
  default = ["sto", "yto", "sgp", "syd", "sao"]
}
