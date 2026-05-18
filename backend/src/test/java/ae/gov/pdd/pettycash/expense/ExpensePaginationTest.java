package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.PostgresTestContainerConfig;
import ae.gov.pdd.pettycash.common.Money;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Cursor pagination on the expense feed. See CLAUDE.md §9.
 *
 * <p>Verifies that:
 * <ul>
 *   <li>25 seed rows split as 10 + 10 + 5 with limit=10 across three cursor calls.</li>
 *   <li>Ordering is stable, newest first by (occurredAt DESC, id DESC).</li>
 *   <li>No duplicates across pages, every row appears exactly once.</li>
 *   <li>Malformed cursor → INVALID_CURSOR.</li>
 * </ul>
 */
@DataJpaTest(showSql = false)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Import(PostgresTestContainerConfig.class)
@Testcontainers
class ExpensePaginationTest {

    private static final UUID TRIP_ID = UUID.fromString("cccccccc-0000-0000-0000-000000000001");
    private static final UUID MEMBER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID SOURCE_ID = UUID.fromString("aaaaaaaa-0000-0000-0000-000000000001");
    private static final UUID CATEGORY_ID = UUID.fromString("bbbbbbbb-0000-0000-0000-000000000001");

    @Autowired ExpenseRepository expenses;

    @Test
    void walkAllPagesWithLimit10() {
        List<UUID> inserted = seed(25);

        // Page 1
        List<Expense> p1 = expenses.findFirstPageByTripId(TRIP_ID, PageRequest.of(0, 11));
        // The repo returns limit+1 to detect "has more"; service trims. Trim here too for the test.
        boolean hasMore1 = p1.size() > 10;
        List<Expense> page1 = hasMore1 ? p1.subList(0, 10) : p1;
        assertThat(page1).hasSize(10);
        assertThat(hasMore1).isTrue();
        assertOrdered(page1);

        // Page 2
        Expense cut1 = page1.get(page1.size() - 1);
        List<Expense> p2 = expenses.findPageByTripId(TRIP_ID, cut1.getOccurredAt(), cut1.getId(),
            PageRequest.of(0, 11));
        boolean hasMore2 = p2.size() > 10;
        List<Expense> page2 = hasMore2 ? p2.subList(0, 10) : p2;
        assertThat(page2).hasSize(10);
        assertThat(hasMore2).isTrue();
        assertOrdered(page2);

        // Page 3 (tail)
        Expense cut2 = page2.get(page2.size() - 1);
        List<Expense> p3 = expenses.findPageByTripId(TRIP_ID, cut2.getOccurredAt(), cut2.getId(),
            PageRequest.of(0, 11));
        boolean hasMore3 = p3.size() > 10;
        List<Expense> page3 = hasMore3 ? p3.subList(0, 10) : p3;
        assertThat(page3).hasSize(5);
        assertThat(hasMore3).isFalse();
        assertOrdered(page3);

        // No duplicates, no missing rows.
        List<UUID> walked = new ArrayList<>();
        page1.forEach(e -> walked.add(e.getId()));
        page2.forEach(e -> walked.add(e.getId()));
        page3.forEach(e -> walked.add(e.getId()));
        assertThat(walked).hasSize(25).doesNotHaveDuplicates();
        assertThat(walked).containsExactlyInAnyOrderElementsOf(inserted);
    }

    @Test
    void invalidCursorIsRejected() {
        assertThatThrownBy(() -> CursorCodec.decode("not-base64-!!"))
            .hasMessageContaining("Cursor could not be decoded");
        assertThatThrownBy(() -> CursorCodec.decode(""))
            .hasMessageContaining("blank");
    }

    @Test
    void cursorRoundTrip() {
        OffsetDateTime ts = OffsetDateTime.parse("2026-05-10T12:00:00+04:00");
        UUID id = UUID.randomUUID();
        String enc = CursorCodec.encode(ts, id);
        CursorCodec.Cursor c = CursorCodec.decode(enc);
        assertThat(c.id()).isEqualTo(id);
        assertThat(c.occurredAt().toInstant()).isEqualTo(ts.toInstant());
    }

    private void assertOrdered(List<Expense> page) {
        for (int i = 1; i < page.size(); i++) {
            Expense prev = page.get(i - 1);
            Expense cur = page.get(i);
            int cmpTs = prev.getOccurredAt().compareTo(cur.getOccurredAt());
            assertThat(cmpTs >= 0).as("occurredAt descending at index " + i).isTrue();
            if (cmpTs == 0) {
                assertThat(prev.getId().compareTo(cur.getId()) > 0)
                    .as("id descending as tie-breaker at index " + i).isTrue();
            }
        }
    }

    private List<UUID> seed(int n) {
        // Use a fixed base instant so tests are deterministic.
        OffsetDateTime base = OffsetDateTime.parse("2026-05-01T08:00:00+04:00");
        List<UUID> ids = new ArrayList<>(n);
        for (int i = 0; i < n; i++) {
            Expense e = new Expense();
            UUID id = UUID.randomUUID();
            e.setId(id);
            e.setTripId(TRIP_ID);
            e.setUserId(MEMBER_ID);
            e.setSourceId(SOURCE_ID);
            e.setCategoryId(CATEGORY_ID);
            e.setCategoryCode("FOOD");
            e.setAmount(Money.of(10000L + i, "SAR"));
            e.setQuantity(1);
            e.setUnitCostAmount(10000L + i);
            e.setDetails("seed-" + i);
            // Spread across distinct timestamps for a fully ordered set.
            e.setOccurredAt(base.plusMinutes(i));
            e.setCreatedAt(base.plusMinutes(i));
            e.setUpdatedAt(base.plusMinutes(i));
            expenses.save(e);
            ids.add(id);
        }
        return ids;
    }
}
