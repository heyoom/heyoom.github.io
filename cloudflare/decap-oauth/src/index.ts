type Env = {
  CMS_URL?: string;
  GITHUB_CLIENT_ID?: string;
  GITHUB_CLIENT_SECRET?: string;
  GITHUB_OAUTH_SCOPE?: string;
};

type OAuthStatus = "success" | "error";

type CallbackPayload =
  | {
      token: string;
      provider: "github";
    }
  | {
      error: string;
      provider: "github";
    };

type GitHubTokenResponse = {
  access_token?: string;
  error?: string;
  error_description?: string;
};

type ResponseHeaders = Record<string, string>;

const githubAuthorizeUrl = "https://github.com/login/oauth/authorize";
const githubTokenUrl = "https://github.com/login/oauth/access_token";
const stateCookieName = "moyorun_decap_oauth_state";
const stateTtlSeconds = 600;

const securityHeaders: ResponseHeaders = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer"
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);

      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: securityHeaders });
      }

      if (request.method !== "GET") {
        return textResponse("Method not allowed", 405);
      }

      if (url.pathname === "/auth") {
        return handleAuth(url, env);
      }

      if (url.pathname === "/callback") {
        return handleCallback(request, url, env);
      }

      if (url.pathname === "/health") {
        return jsonResponse({ ok: true });
      }

      return textResponse("Decap OAuth provider", 200);
    } catch (error) {
      console.error(
        JSON.stringify({
          event: "oauth_unhandled_error",
          error: error instanceof Error ? error.message : String(error)
        })
      );
      return textResponse("Internal server error", 500);
    }
  }
};

function handleAuth(url: URL, env: Env): Response {
  const provider = url.searchParams.get("provider");
  if (provider !== "github") {
    return textResponse("Invalid provider", 400);
  }

  const clientId = requireEnv(env.GITHUB_CLIENT_ID, "GITHUB_CLIENT_ID");
  const scope = getOAuthScope(url, env);
  const state = crypto.randomUUID();
  const redirectUri = `${url.origin}/callback`;
  const githubUrl = new URL(githubAuthorizeUrl);

  githubUrl.searchParams.set("client_id", clientId);
  githubUrl.searchParams.set("redirect_uri", redirectUri);
  githubUrl.searchParams.set("scope", scope);
  githubUrl.searchParams.set("state", state);

  return new Response(null, {
    status: 302,
    headers: {
      ...securityHeaders,
      "Cache-Control": "no-store",
      Location: githubUrl.toString(),
      "Set-Cookie": buildStateCookie(state)
    }
  });
}

async function handleCallback(request: Request, url: URL, env: Env): Promise<Response> {
  const callbackHeaders = {
    ...securityHeaders,
    "Cache-Control": "no-store",
    "Set-Cookie": clearStateCookie()
  };

  const oauthError = url.searchParams.get("error");
  if (oauthError) {
    return callbackScriptResponse(
      env,
      "error",
      { error: oauthError, provider: "github" },
      callbackHeaders
    );
  }

  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  if (!code || !state) {
    return callbackScriptResponse(
      env,
      "error",
      { error: "missing_code_or_state", provider: "github" },
      callbackHeaders
    );
  }

  const expectedState = getCookie(request, stateCookieName);
  if (!expectedState || expectedState !== state) {
    return callbackScriptResponse(
      env,
      "error",
      { error: "invalid_state", provider: "github" },
      callbackHeaders
    );
  }

  let token: string;
  try {
    token = await exchangeGitHubToken(url, code, env);
  } catch (error) {
    console.error(
      JSON.stringify({
        event: "github_token_exchange_failed",
        error: error instanceof Error ? error.message : String(error)
      })
    );
    return callbackScriptResponse(
      env,
      "error",
      { error: "github_token_exchange_failed", provider: "github" },
      callbackHeaders
    );
  }

  return callbackScriptResponse(
    env,
    "success",
    { token, provider: "github" },
    callbackHeaders
  );
}

async function exchangeGitHubToken(url: URL, code: string, env: Env): Promise<string> {
  const clientId = requireEnv(env.GITHUB_CLIENT_ID, "GITHUB_CLIENT_ID");
  const clientSecret = requireEnv(env.GITHUB_CLIENT_SECRET, "GITHUB_CLIENT_SECRET");
  const response = await fetch(githubTokenUrl, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      client_id: clientId,
      client_secret: clientSecret,
      code,
      redirect_uri: `${url.origin}/callback`
    })
  });

  const body = (await response.json()) as GitHubTokenResponse;
  if (!response.ok || !body.access_token) {
    const error = body.error_description || body.error || `github_token_${response.status}`;
    throw new Error(error);
  }

  return body.access_token;
}

function callbackScriptResponse(
  env: Env,
  status: OAuthStatus,
  payload: CallbackPayload,
  headers: ResponseHeaders
): Response {
  const targetOrigin = getCmsOrigin(env);
  const message = `authorization:github:${status}:${JSON.stringify(payload)}`;

  return new Response(
    `<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <title>Decap CMS GitHub authorization</title>
  <script>
    (function () {
      var targetOrigin = ${JSON.stringify(targetOrigin)};
      var message = ${JSON.stringify(message)};
      var sent = false;
      var complete = function () {
        if (sent) return;
        sent = true;
        window.removeEventListener("message", complete, false);
        window.opener.postMessage(message, targetOrigin);
        window.close();
      };

      if (!window.opener) {
        document.addEventListener("DOMContentLoaded", function () {
          document.body.textContent = "관리자 창을 다시 열어 인증을 시도해주세요.";
        });
        return;
      }

      window.addEventListener("message", complete, false);
      window.opener.postMessage("authorizing:github", targetOrigin);
      window.setTimeout(complete, 3000);
    })();
  </script>
</head>
<body>
  <p>Authorizing Decap CMS...</p>
</body>
</html>`,
    {
      status: 200,
      headers: {
        ...headers,
        "Content-Type": "text/html; charset=utf-8"
      }
    }
  );
}

function getOAuthScope(url: URL, env: Env): string {
  const requestedScope = url.searchParams.get("scope") || env.GITHUB_OAUTH_SCOPE || "repo";
  const scope = requestedScope
    .split(/[,\s]+/)
    .map((value) => value.trim())
    .filter(Boolean)
    .join(" ");

  if (!scope || !/^[A-Za-z0-9:_\-\s]+$/.test(scope)) {
    throw new Error("Invalid GitHub OAuth scope");
  }

  return scope;
}

function getCmsOrigin(env: Env): string {
  const cmsUrl = requireEnv(env.CMS_URL, "CMS_URL");
  return new URL(cmsUrl).origin;
}

function requireEnv(value: string | undefined, name: string): string {
  if (!value) {
    throw new Error(`Missing ${name}`);
  }

  return value;
}

function buildStateCookie(state: string): string {
  return `${stateCookieName}=${encodeURIComponent(
    state
  )}; Path=/callback; Max-Age=${stateTtlSeconds}; HttpOnly; Secure; SameSite=Lax`;
}

function clearStateCookie(): string {
  return `${stateCookieName}=; Path=/callback; Max-Age=0; HttpOnly; Secure; SameSite=Lax`;
}

function getCookie(request: Request, name: string): string | null {
  const cookieHeader = request.headers.get("Cookie");
  if (!cookieHeader) {
    return null;
  }

  for (const part of cookieHeader.split(";")) {
    const [cookieName, ...cookieValue] = part.trim().split("=");
    if (cookieName === name) {
      return decodeURIComponent(cookieValue.join("="));
    }
  }

  return null;
}

function textResponse(body: string, status: number): Response {
  return new Response(body, {
    status,
    headers: {
      ...securityHeaders,
      "Content-Type": "text/plain; charset=utf-8"
    }
  });
}

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: {
      ...securityHeaders,
      "Content-Type": "application/json; charset=utf-8"
    }
  });
}
