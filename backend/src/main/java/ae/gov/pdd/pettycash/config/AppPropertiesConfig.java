package ae.gov.pdd.pettycash.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableConfigurationProperties({JwtProperties.class, StorageProperties.class})
public class AppPropertiesConfig {}
