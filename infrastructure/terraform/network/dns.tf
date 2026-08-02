# wg.ahara.io is owned by the ahara-vpn stack (imported there during the
# endpoint migration); it was state-rm'd from this state before this removal
# applied so the destroy never touched the live record.

# Note: the apex A record for ahara.io lives in services/dns.tf — Cognito's
# custom domain needs to explicitly depend on it, which is only possible
# if it lives in the same module as the cognito user pool domain resource.
