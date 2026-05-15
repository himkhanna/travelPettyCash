package ae.gov.pdd.pettycash.config;

import ae.gov.pdd.pettycash.expense.ExpenseCategory;
import ae.gov.pdd.pettycash.expense.ExpenseCategoryRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/** Seeds the 8 standard categories from mobile/assets/demo/categories.json. */
@Component
@Order(25)
@ConditionalOnProperty(name = "pdd.demo.seed", havingValue = "true")
public class DemoCategorySeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DemoCategorySeeder.class);

    private final ExpenseCategoryRepository categories;

    public DemoCategorySeeder(ExpenseCategoryRepository categories) {
        this.categories = categories;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        int seeded = 0;
        for (Seed s : SEEDS) {
            if (categories.existsByCode(s.code())) continue;
            categories.save(new ExpenseCategory(
                UUID.randomUUID(), s.code(), s.nameEn(), s.nameAr(), s.iconKey()
            ));
            seeded++;
        }
        log.info("DemoCategorySeeder seeded {} category/categories.", seeded);
    }

    private record Seed(String code, String nameEn, String nameAr, String iconKey) {}

    private static final List<Seed> SEEDS = List.of(
        new Seed("FOOD",          "Food",          "طعام",     "cutlery"),
        new Seed("TRANSPORT",     "Transport",     "نقل",       "car"),
        new Seed("HOTEL",         "Hotel",         "فندق",      "bed"),
        new Seed("PHONE",         "Phone",         "هاتف",      "phone"),
        new Seed("ENTERTAINMENT", "Entertainment", "ترفيه",    "ticket"),
        new Seed("TIPS",          "Tips",          "إكراميات", "coin"),
        new Seed("TRAVEL",        "Travel",        "سفر",       "plane"),
        new Seed("OTHERS",        "Others",        "أخرى",     "dots")
    );
}
