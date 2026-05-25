package ae.gov.pdd.pettycash;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class PettyCashApplication {
    public static void main(String[] args) {
        SpringApplication.run(PettyCashApplication.class, args);
    }
}
