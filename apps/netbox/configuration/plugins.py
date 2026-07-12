# Baked into the image. See README.md. netbox_branching MUST be last.
PLUGINS = [
    "netbox_acls",
    "netbox_branching",
]

# Wrap the env-built DATABASES so branching can swap PG schema per branch.
from netbox.configuration.configuration import DATABASES  # noqa: E402
from netbox_branching.utilities import DynamicSchemaDict  # noqa: E402

DATABASES = DynamicSchemaDict(DATABASES)
DATABASE_ROUTERS = ["netbox_branching.database.BranchAwareRouter"]
