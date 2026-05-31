package ae.gov.pdd.pettycash;

import ae.gov.pdd.pettycash.auth.sso.DubaiGovProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
@EnableConfigurationProperties(DubaiGovProperties.class)
public class PettyCashApplication {
    public static void main(String[] args) {
        SpringApplication.run(PettyCashApplication.class, args);
    }
}
