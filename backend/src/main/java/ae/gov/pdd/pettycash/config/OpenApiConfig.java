package ae.gov.pdd.pettycash.config;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import io.swagger.v3.oas.annotations.info.Contact;
import io.swagger.v3.oas.annotations.info.Info;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import io.swagger.v3.oas.annotations.servers.Server;
import org.springframework.context.annotation.Configuration;

/**
 * Springdoc OpenAPI metadata. See CLAUDE.md §9.
 * UI at /swagger-ui.html, spec at /v3/api-docs.
 */
@Configuration
@OpenAPIDefinition(
    info = @Info(
        title = "PDD Petty Cash API",
        version = "0.1.0",
        description = "REST API for the PDD Petty Cash (Travel Expense Management) app.",
        contact = @Contact(name = "PDD Engineering", email = "engineering@pdd.gov.ae")
    ),
    servers = {
        @Server(url = "http://localhost:8080/api/v1", description = "Local Spring Boot")
    }
)
@SecurityScheme(
    name = "bearerAuth",
    type = SecuritySchemeType.HTTP,
    scheme = "bearer",
    bearerFormat = "JWT"
)
public class OpenApiConfig {}
