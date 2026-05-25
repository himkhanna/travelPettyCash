package ae.gov.pdd.pettycash.ocr;

import ae.gov.pdd.pettycash.common.error.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;

/**
 * Stateless receipt OCR — takes raw bytes, returns suggested fields.
 * No expense ID required; the mobile add-expense flow can call this
 * before the expense is created so the user reviews the prefill first.
 *
 * Multipart limit defers to Spring Boot's default (1MB file / 10MB
 * request). Receipts are already compressed to ~1MB on the client per
 * CLAUDE.md §11, so the default fits.
 */
@RestController
@RequestMapping("/api/v1/ocr")
class OcrController {

    private final ReceiptOcrService service;

    OcrController(ReceiptOcrService service) {
        this.service = service;
    }

    @PostMapping("/receipt")
    public OcrResult receipt(@RequestParam("file") MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new ApiException(
                HttpStatus.BAD_REQUEST, "ocr/empty-file",
                "Empty file", "No image was provided in the 'file' part."
            );
        }
        try {
            return service.ocr(file.getBytes());
        } catch (IOException e) {
            throw new ApiException(
                HttpStatus.BAD_REQUEST, "ocr/read-failed",
                "Could not read upload", e.getMessage()
            );
        }
    }
}
