# Continent => Azure paired regions. cidr_index gives each region a unique 10.<cidr_index>.0.0/16
# so any two regions can be peered later (e.g. Kafka MirrorMaker2 between pairs).
#
# Checked against this subscription with `az vm list-skus` (2026-11-07):
#   - brazilsoutheast: restricted region - every VM SKU is NotAvailableForSubscription until an
#     access request is approved. It is Brazil South's only in-continent partner (the official pair
#     is southcentralus). Fallback if access is denied: chilecentral (open, but not an Azure pair).
#   - northeurope is blocked for this subscription, so EU uses the uksouth/ukwest pair instead of
#     northeurope/westeurope.
#   - centralindia/eastus2/westeurope/brazilsouth have zone-level restrictions only; clusters are
#     non-zonal in dev, so this doesn't matter until zones are enabled.
locals {
  continents = {
    na = {
      primary   = { location = "eastus2", short = "eus2", cidr_index = 10 }
      secondary = { location = "centralus", short = "cus", cidr_index = 11 }
    }
    sa = {
      primary   = { location = "brazilsouth", short = "brs", cidr_index = 20 }
      secondary = { location = "brazilsoutheast", short = "brse", cidr_index = 21 }
    }
    eu = {
      primary   = { location = "uksouth", short = "uks", cidr_index = 30 }
      secondary = { location = "ukwest", short = "ukw", cidr_index = 31 }
    }
    as = {
      primary   = { location = "centralindia", short = "inc", cidr_index = 40 }
      secondary = { location = "southindia", short = "ins", cidr_index = 41 }
    }
    af = {
      primary   = { location = "southafricanorth", short = "san", cidr_index = 50 }
      secondary = { location = "southafricawest", short = "saw", cidr_index = 51 }
    }
  }
}
