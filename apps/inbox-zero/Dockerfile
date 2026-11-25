# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Upstream hardcodes the TypeSafe System One URL (apps/web/utils/decision-model/decision-model.ts),
# so `typesafe:` decision models cannot go through a gateway. TYPESAFE_SYSTEMONE_URL overrides it;
# unset keeps upstream behaviour.
ARG VERSION
FROM elie222/inbox-zero:${VERSION}

RUN set -eu; \
    files="$(grep -rl 'url:"https://api.typesafe.ai/v1/systemone"' /app/apps/web/.next/server)"; \
    test -n "$files"; \
    for f in $files; do \
      sed -i 's#url:"https://api.typesafe.ai/v1/systemone"#url:process.env.TYPESAFE_SYSTEMONE_URL||"https://api.typesafe.ai/v1/systemone"#g' "$f"; \
    done; \
    ! grep -rq 'url:"https://api.typesafe.ai/v1/systemone"' /app/apps/web/.next/server
