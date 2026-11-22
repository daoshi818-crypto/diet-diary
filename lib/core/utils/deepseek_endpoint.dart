bool isDeepSeekEndpoint(Uri endpoint) =>
    endpoint.scheme == 'https' &&
    endpoint.host == 'api.deepseek.com' &&
    endpoint.port == 443 &&
    endpoint.userInfo.isEmpty &&
    RegExp(r'^/(?:v1/|beta/)?chat/completions$').hasMatch(endpoint.path);
