# I keep this backend partial because Terraform won't read input vars here.
# Pass bucket and prefix from `make init` so the repo stays easy to move around.
terraform {
  backend "gcs" {}
}
