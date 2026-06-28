# MoyoRun Decap OAuth Worker

GitHub Pages에서 Decap CMS GitHub backend를 쓰기 위한 Cloudflare Worker OAuth provider입니다.

## 흐름

1. Decap CMS가 `/auth?provider=github&scope=repo`를 엽니다.
2. Worker가 GitHub OAuth authorize URL로 redirect합니다.
3. GitHub가 Worker `/callback`으로 돌아옵니다.
4. Worker가 GitHub token endpoint에서 access token을 받아 Decap popup에 전달합니다.
5. Decap CMS가 `heyoom/heyoom.github.io`의 `main` branch에 commit합니다.

## 배포 순서

```bash
cd cloudflare/decap-oauth
wrangler login
wrangler deploy
```

배포된 Worker URL은 다음과 같습니다.

```text
https://moyorun-decap-oauth.delver.workers.dev
```

이 Worker URL을 기준으로 GitHub OAuth App을 만듭니다.

- Homepage URL: `https://moyorun.com/admin/`
- Authorization callback URL: `https://moyorun-decap-oauth.delver.workers.dev/callback`

GitHub OAuth App 생성 후 secret을 등록합니다.

```bash
cd cloudflare/decap-oauth
wrangler secret put GITHUB_CLIENT_ID
wrangler secret put GITHUB_CLIENT_SECRET
wrangler deploy
```

마지막으로 `static/admin/config.yml`의 GitHub backend에 Worker URL을 연결합니다.

```yaml
backend:
  name: github
  repo: heyoom/heyoom.github.io
  branch: main
  base_url: https://moyorun-decap-oauth.delver.workers.dev
  auth_endpoint: auth
```

## 운영 값

- `CMS_URL`: Decap 관리자 URL. 기본값은 `https://moyorun.com/admin/`
- `GITHUB_OAUTH_SCOPE`: Decap이 요청한 scope가 없을 때 사용할 기본 scope. 기본값은 `repo`
- `GITHUB_CLIENT_ID`: GitHub OAuth App Client ID. Wrangler secret으로 등록
- `GITHUB_CLIENT_SECRET`: GitHub OAuth App Client secret. Wrangler secret으로 등록

비밀값은 repo에 커밋하지 않습니다.
