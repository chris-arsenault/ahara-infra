# Arconis detaches ownership first. Import blocks belong in the root module, while the shared
# resources and their provider remain in services. Existing objects and users are retained.
import {
  to = module.services.auth0_connection.accounts
  id = module.services.auth0_existing_accounts_id
}

import {
  to = module.services.auth0_action.require_activation
  id = module.services.auth0_existing_activation_id
}

import {
  to = module.services.auth0_trigger_action.require_activation
  id = "post-login::${module.services.auth0_existing_activation_id}"
}
