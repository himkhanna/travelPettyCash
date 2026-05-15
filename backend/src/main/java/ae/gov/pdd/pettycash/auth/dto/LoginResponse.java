package ae.gov.pdd.pettycash.auth.dto;

public record LoginResponse(MeResponse user, AuthTokens tokens) {}
