package ae.gov.pdd.pettycash.ocr;

import org.springframework.stereotype.Component;

import java.text.Normalizer;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Deterministic receipt-to-category classifier. Given the merchant name
 * and the raw OCR text, it scores each {@code ExpenseCategory} code by how
 * many of its keywords / known brands appear, and returns the best match.
 *
 * <p>This is intentionally <b>not</b> machine learning — it's a keyword and
 * brand lookup table (English + Arabic + common UAE/KSA merchants). It runs
 * on-prem with no model, no GPU, and no data leaving the tenant, which keeps
 * it inside the deterministic-first rule in CLAUDE.md §3 while still giving
 * the Add-Expense form an "auto-tagged" feel.
 *
 * <p>Category codes are the stable seed codes from {@code V004} /
 * CLAUDE.md §5: {@code FOOD TRANSPORT HOTEL PHONE ENTERTAINMENT TIPS TRAVEL
 * OTHERS}. When nothing matches it returns {@code null} so the caller can
 * leave the form's own default untouched rather than guessing {@code OTHERS}.
 */
@Component
public class ReceiptCategorizer {

    /**
     * Category code → keywords. Insertion order is the deterministic
     * tie-break: when two categories score equally, the one declared first
     * here wins (so a hotel that also sells food reads as HOTEL). Keywords
     * are matched case-insensitively against the accent-stripped,
     * lower-cased text; Arabic terms are matched as-is.
     */
    private static final Map<String, List<String>> KEYWORDS = new LinkedHashMap<>();

    static {
        KEYWORDS.put("HOTEL", List.of(
            "hotel", "hotels", "inn", "resort", "suites", "motel", "lodge",
            "accommodation", "rooms", "guest house",
            "hilton", "marriott", "hyatt", "sheraton", "rotana", "radisson",
            "ritz", "ritz-carlton", "fairmont", "novotel", "ibis", "intercontinental",
            "movenpick", "jumeirah", "kempinski", "westin", "le meridien",
            "فندق", "نزل", "منتجع"
        ));
        KEYWORDS.put("TRAVEL", List.of(
            "airline", "airlines", "airways", "flight", "airport", "boarding",
            "boarding pass", "baggage", "e-ticket", "eticket", "visa fee",
            "emirates", "etihad", "flydubai", "qatar airways", "saudia",
            "gulf air", "air arabia", "turkish airlines", "lufthansa",
            "طيران", "رحلة", "مطار", "تأشيرة", "بطاقة صعود"
        ));
        KEYWORDS.put("TRANSPORT", List.of(
            "taxi", "cab", "uber", "careem", "lyft", "bolt", "metro", "tram",
            "bus", "train", "limousine", "limo", "car rental", "rent a car",
            "hertz", "avis", "europcar", "sixt", "fuel", "petrol", "gasoline",
            "gas station", "adnoc", "enoc", "eppco", "parking", "toll", "salik",
            "darb", "rta",
            "تاكسي", "أجرة", "مواصلات", "وقود", "بنزين", "موقف", "حافلة"
        ));
        KEYWORDS.put("FOOD", List.of(
            "restaurant", "cafe", "coffee", "bistro", "grill",
            "kitchen", "dining", "diner", "eatery", "bakery", "patisserie",
            "catering", "shawarma", "pizza", "burger", "starbucks", "costa",
            "tim hortons", "kfc", "mcdonald", "mcdonalds", "subway",
            "carrefour", "lulu", "spinneys", "waitrose", "supermarket",
            "grocery", "food court",
            "مطعم", "مقهى", "قهوة", "مخبز", "طعام", "كافيه", "شاورما"
        ));
        KEYWORDS.put("PHONE", List.of(
            "etisalat", "du ", "telecom", "telecommunication", "mobile",
            "sim card", "sim", "recharge", "top up", "top-up", "data plan",
            "roaming", "prepaid", "postpaid", "stc",
            "اتصالات", "شريحة", "هاتف", "تعبئة"
        ));
        KEYWORDS.put("ENTERTAINMENT", List.of(
            "cinema", "movie", "movies", "theatre", "theater", "vox", "reel",
            "museum", "gallery", "amusement", "theme park", "ticket", "tickets",
            "show", "concert", "entertainment", "leisure",
            "سينما", "ترفيه", "متحف", "تذكرة", "تذاكر"
        ));
        KEYWORDS.put("TIPS", List.of(
            "tip", "tips", "gratuity", "service charge", "service fee",
            "بقشيش", "إكرامية", "خدمة"
        ));
        // OTHERS is the implicit fallback — no keywords; we return null when
        // nothing scores so the form keeps its default rather than guessing.
    }

    /**
     * @param vendor  the merchant line OCR pulled from the top of the receipt
     *                (may be null)
     * @param rawText the full OCR text (may be null)
     * @return a category code from the seed set, or {@code null} when nothing
     *         matched confidently
     */
    public String categorize(String vendor, String rawText) {
        String hay = normalize((vendor == null ? "" : vendor + " ")
            + (rawText == null ? "" : rawText));
        if (hay.isBlank()) {
            return null;
        }

        String best = null;
        int bestScore = 0;
        for (Map.Entry<String, List<String>> e : KEYWORDS.entrySet()) {
            int score = 0;
            for (String kw : e.getValue()) {
                if (hay.contains(kw)) {
                    score++;
                }
            }
            // Strictly-greater keeps the first (highest-priority) category on
            // ties, since the map is a LinkedHashMap iterated in declaration
            // order.
            if (score > bestScore) {
                bestScore = score;
                best = e.getKey();
            }
        }
        return best;
    }

    /**
     * Lower-case and strip diacritics so "Café" matches "cafe". Arabic
     * letters are left intact (NFD on Arabic separates harakat, which we
     * then drop — harmless for our keyword set, which uses bare letters).
     */
    private static String normalize(String s) {
        String lower = s.toLowerCase(Locale.ROOT);
        String decomposed = Normalizer.normalize(lower, Normalizer.Form.NFD);
        // Drop combining marks (Latin accents + Arabic harakat).
        return decomposed.replaceAll("\\p{M}+", "").trim();
    }
}
