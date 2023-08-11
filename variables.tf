variable "region" {
  description = "AWS region"
  type        = string
}

variable "awsprofile" {
  type = string
}

variable "instancetype" {
  type = list(string)
}
variable "min_instance" {
  type = string
}
variable "max_instance" {
  type = string
}
variable "desired_instance" {
  type = string
}