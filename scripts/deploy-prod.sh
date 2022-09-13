aws s3 cp ./index.html s3://mouse-sentinel-landing-page/ --acl public-read
aws cloudfront create-invalidation --distribution-id E1521LYDIFGJXW --paths "/*"