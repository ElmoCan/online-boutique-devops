terraform {
  backend "s3" {
    bucket       = "online-boutique-dev-tfstate-471623014584-ue1"
    key          = "online-boutique/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
