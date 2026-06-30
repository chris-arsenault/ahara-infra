import {
  to = module.services.aws_cloudwatch_log_group.db_migrate
  id = "/aws/lambda/ahara-db-migrate"
}

import {
  to = module.services.aws_cloudwatch_log_group.db_migrate_truenas
  id = "/aws/lambda/ahara-db-migrate-truenas"
}

import {
  to = module.services.aws_cloudwatch_log_group.komodo_proxy
  id = "/aws/lambda/ahara-komodo-proxy"
}
