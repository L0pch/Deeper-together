import type { NextConfig } from "next";

type ResponseHeader = { key: string; value: string };

function getSupabaseConnectionSources(): string[] {
  const configuredUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;

  if (!configuredUrl) return [];

  try {
    const httpUrl = new URL(configuredUrl);
    if (httpUrl.protocol !== "http:" && httpUrl.protocol !== "https:") return [];

    const websocketUrl = new URL(httpUrl.origin);
    websocketUrl.protocol = httpUrl.protocol === "https:" ? "wss:" : "ws:";

    return [httpUrl.origin, websocketUrl.origin];
  } catch {
    return [];
  }
}

const isDevelopment = process.env.NODE_ENV === "development";
const connectSources = ["'self'", ...getSupabaseConnectionSources()];
if (isDevelopment) connectSources.push("ws:");

const contentSecurityPolicy = [
  "default-src 'self'",
  "base-uri 'self'",
  `connect-src ${[...new Set(connectSources)].join(" ")}`,
  "font-src 'self' data:",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "frame-src 'none'",
  "img-src 'self' blob: data:",
  "manifest-src 'self'",
  "media-src 'none'",
  "object-src 'none'",
  `script-src 'self' 'unsafe-inline'${isDevelopment ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline'",
  "worker-src 'self' blob:",
].join("; ");

const securityHeaders: ResponseHeader[] = [
  {
    key: "Content-Security-Policy",
    value: contentSecurityPolicy,
  },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=(), browsing-topics=()",
  },
  {
    key: "Referrer-Policy",
    value: "strict-origin-when-cross-origin",
  },
  {
    key: "X-Content-Type-Options",
    value: "nosniff",
  },
  {
    key: "X-Frame-Options",
    value: "DENY",
  },
];

if (process.env.VERCEL_ENV === "production") {
  securityHeaders.push({
    key: "Strict-Transport-Security",
    value: "max-age=31536000",
  });
}

const nextConfig: NextConfig = {
  poweredByHeader: false,
  async headers() {
    return [
      {
        source: "/:path*",
        headers: securityHeaders,
      },
    ];
  },
};

export default nextConfig;
