package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.common.error.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class CategoryController {

    private final ExpenseCategoryRepository repo;

    public CategoryController(ExpenseCategoryRepository repo) {
        this.repo = repo;
    }

    @GetMapping("/categories")
    public List<CategoryDto> list() {
        return repo.findByActiveTrueOrderByCode().stream()
            .map(CategoryDto::from)
            .toList();
    }

    @PostMapping("/categories")
    @PreAuthorize("hasRole('ADMIN') or hasRole('SUPER_ADMIN')")
    public CategoryDto create(@Valid @RequestBody CreateCategoryRequest body) {
        String code = body.code().toUpperCase();
        if (repo.existsByCode(code)) {
            throw new ApiException(
                HttpStatus.CONFLICT,
                "categories/duplicate-code",
                "Duplicate category code",
                "A category with code '" + code + "' already exists."
            );
        }
        ExpenseCategory saved = repo.save(new ExpenseCategory(
            UUID.randomUUID(), code, body.nameEn(), body.nameAr(), body.iconKey()
        ));
        return CategoryDto.from(saved);
    }

    public record CategoryDto(
        UUID id, String code, String nameEn, String nameAr, String iconKey, boolean active
    ) {
        static CategoryDto from(ExpenseCategory c) {
            return new CategoryDto(
                c.getId(), c.getCode(), c.getNameEn(), c.getNameAr(),
                c.getIconKey(), c.isActive()
            );
        }
    }

    public record CreateCategoryRequest(
        @NotBlank @Pattern(regexp = "[A-Z][A-Z0-9_]{1,31}") String code,
        @NotBlank @Size(max = 64) String nameEn,
        @NotBlank @Size(max = 64) String nameAr,
        @NotBlank @Size(max = 32) String iconKey
    ) {}
}
