variable "data_buckets" {
  type    = list(string)
  default = ["emkidev-bronze-hsl", "emkidev-silver-hsl", "emkidev-gold-hsl", "emkidev-reference-hsl", "emkidev-results-hsl"]
}

resource "aws_s3_bucket" "data_bucket" {
  count  = length(var.data_buckets)
  bucket = var.data_buckets[count.index]

  tags = {
    Name        = var.data_buckets[count.index]
    Environment = "Dev"
  }
}

# Allow public read on results bucket for the public dashboard JSON
resource "aws_s3_bucket_public_access_block" "results_public" {
  bucket = aws_s3_bucket.data_bucket[4].id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false  # Allow public bucket policy
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "results_public_read" {
  bucket = aws_s3_bucket.data_bucket[4].id

  depends_on = [aws_s3_bucket_public_access_block.results_public]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadStats"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.data_bucket[4].arn}/public/*"
      }
    ]
  })
}
