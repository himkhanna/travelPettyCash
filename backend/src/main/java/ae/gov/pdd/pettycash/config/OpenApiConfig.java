package ae.gov.pdd.pettycash.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI pddOpenApi() {
        SecurityScheme bearer = new SecurityScheme()
            .type(SecurityScheme.Type.HTTP)
            .scheme("bearer")
            .bearerFormat("JWT");

        return new OpenAPI()
            .info(new Info()
                .title("PDD Delegation Expenses API")
                .description("Travel funds allocation and expense submission for the Protocol Department, Government of Dubai.")
                .version("v1")
                .license(new License().name("Internal").url("https://pdd.gov.ae"))
            )
            .components(new Components().addSecuritySchemes("bearerAuth", bearer))
            .addSecurityItem(new SecurityRequirement().addList("bearerAuth"));
    }
}
