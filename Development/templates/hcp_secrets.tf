# Enable K/V v2 secrets engine at 'kv-v2'
resource "vault_mount" "test" {
  path = "test"
  type = "kv"
}

# Enable Transit secrets engine at 'transit'
resource "vault_mount" "transit" {
  path = "transit"
  type = "transit"
}

# # Creating an encryption key named 'payment'
# resource "vault_transit_secret_backend_key" "key" {
#   depends_on = [vault_mount.transit]
#   backend    = "transit"
#   name       = "payment"
#   deletion_allowed = true
# }
