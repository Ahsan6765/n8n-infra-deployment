# =============================================================================
# Key Pair Module – EC2 SSH Key Pair
# =============================================================================

resource "aws_key_pair" "cluster" {
  key_name   = var.key_name
  public_key = var.public_key

  tags = {
    Name = var.key_name
  }
}
