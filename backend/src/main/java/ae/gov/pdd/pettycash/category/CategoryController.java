package ae.gov.pdd.pettycash.category;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

interface CategoryRepository extends JpaRepository<CategoryEntity, String> {
    boolean existsByCode(String code);
}

@RestController
@RequestMapping("/api/v1/categories")
class CategoryController {
    private final CategoryRepository categories;

    CategoryController(CategoryRepository categories) { this.categories = categories; }

    public record CategoryView(
            String id, String code, String nameEn, String nameAr,
            String iconKey, boolean active
    ) {
        static CategoryView of(CategoryEntity c) {
            return new CategoryView(c.getId(), c.getCode(), c.getNameEn(),
                    c.getNameAr(), c.getIconKey(), c.isActive());
        }
    }

    public record CreateCategoryRequest(
            @NotBlank String code,
            @NotBlank String nameEn,
            @NotBlank String nameAr,
            @NotBlank String iconKey
    ) {}

    @GetMapping
    public List<CategoryView> list() {
        return categories.findAll().stream().map(CategoryView::of).toList();
    }

    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<CategoryView> create(@Valid @RequestBody CreateCategoryRequest req) {
        if (categories.existsByCode(req.code().toUpperCase())) {
            throw new IllegalArgumentException("Category code already exists: " + req.code());
        }
        CategoryEntity c = new CategoryEntity(
                "cat-" + UUID.randomUUID().toString().substring(0, 8),
                req.code().toUpperCase(),
                req.nameEn(), req.nameAr(), req.iconKey(), true
        );
        return ResponseEntity.ok(CategoryView.of(categories.save(c)));
    }
}
