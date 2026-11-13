# Shared Ahara identities. Adopt the original Arconis connection in place: users, passwords and
# application data keyed by their Auth0 subjects retain their identities. Deploy Arconis's
# removed blocks first; they detach management without destroying the connection or Action.
data "auth0_connection" "existing_accounts" {
  name                 = "arconis"
  skip_enabled_clients = true
}

resource "auth0_connection" "accounts" {
  # Auth0's internal connection name is retained for existing sessions and clients.
  name                 = "arconis"
  display_name         = "Ahara"
  strategy             = "auth0"
  is_domain_connection = true

  options {
    disable_signup         = false
    brute_force_protection = true
    password_policy        = "fair"

    password_complexity_options {
      min_length = 12
    }

    attributes {
      email {
        profile_required    = true
        verification_method = "otp"
        identifier {
          active = true
        }
        signup {
          status = "required"
          verification {
            active = true
          }
        }
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "auth0_connection_id" {
  name  = "${local.ssm_prefix}/auth0/connection-id"
  type  = "String"
  value = auth0_connection.accounts.id
}

resource "aws_ssm_parameter" "auth0_connection_name" {
  name  = "${local.ssm_prefix}/auth0/connection-name"
  type  = "String"
  value = auth0_connection.accounts.name
}

data "auth0_action" "existing_activation" {
  name = "arconis-require-activation"
}

resource "auth0_action" "require_activation" {
  # Keep the existing Action identity and binding while changing ownership and message.
  name    = "arconis-require-activation"
  runtime = "node22"
  deploy  = true
  code    = file("${path.module}/auth0-actions/require-verified-email.js")

  supported_triggers {
    id      = "post-login"
    version = "v3"
  }
}

resource "auth0_trigger_action" "require_activation" {
  trigger   = "post-login"
  action_id = auth0_action.require_activation.id
}

# Root-level import blocks consume discovered IDs without depending on the resources being imported.
output "auth0_existing_accounts_id" {
  value = data.auth0_connection.existing_accounts.id
}

output "auth0_existing_activation_id" {
  value = data.auth0_action.existing_activation.id
}
