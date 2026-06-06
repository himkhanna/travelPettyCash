package ae.gov.pdd.pettycash.insight;

import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

/**
 * Pure, deterministic spending-insights engine. Given a trip's budget and the
 * list of its expenses it produces a set of flagged {@link Insight}s plus a
 * plain-language narrative — entirely from arithmetic and string templates.
 *
 * <p>There is no machine learning here: it's burn-rate, share-of-total,
 * duplicate grouping and ranking. That keeps it on-prem with no model and no
 * GPU (CLAUDE.md §3) while giving the dashboard an "the system noticed this"
 * feel. All money math stays in {@code long} minor units (CLAUDE.md §6).
 *
 * <p>Rules, in output order:
 * <ol>
 *   <li><b>Budget</b> — over budget (CRITICAL), ≥80% spent (WARNING),
 *       otherwise on-track (INFO). Skipped when no budget is set.</li>
 *   <li><b>Category concentration</b> — when the largest category is ≥40% of
 *       spend (≥60% escalates to WARNING).</li>
 *   <li><b>Possible duplicates</b> — 2+ expenses sharing amount + day +
 *       category (WARNING); up to two such groups reported.</li>
 *   <li><b>Top spender</b> — the highest-spending member when 2+ people have
 *       logged expenses (INFO).</li>
 * </ol>
 */
@Component
public class InsightCalculator {

    public TripInsightsDto calculate(
        String tripName,
        String currency,
        long budgetMinor,
        List<ExpenseFact> expenses,
        Map<String, String> categoryNames,
        Map<UUID, String> userNames
    ) {
        List<Insight> out = new ArrayList<>();
        long totalSpent = 0;
        for (ExpenseFact e : expenses) {
            totalSpent += e.amountMinor();
        }
        int count = expenses.size();

        // No expenses yet -> just the narrative, no flags.
        if (count == 0) {
            return new TripInsightsDto(
                buildNarrative(tripName, currency, budgetMinor, 0, 0,
                    new LinkedHashMap<>(), categoryNames),
                out);
        }

        // 1. Budget burn-rate.
        if (budgetMinor > 0) {
            long pct = Math.round(totalSpent * 100.0 / budgetMinor);
            long remaining = budgetMinor - totalSpent;
            if (totalSpent > budgetMinor) {
                out.add(new Insight("OVER_BUDGET", Insight.CRITICAL, "Over budget",
                    "Spending has exceeded the budget by "
                        + fmt(totalSpent - budgetMinor, currency)
                        + " (" + pct + "% of " + fmt(budgetMinor, currency) + ")."));
            } else if (pct >= 80) {
                out.add(new Insight("BUDGET_BURN", Insight.WARNING, "Budget nearly exhausted",
                    pct + "% of the " + fmt(budgetMinor, currency) + " budget is spent — "
                        + fmt(remaining, currency) + " remaining."));
            } else {
                out.add(new Insight("BUDGET_OK", Insight.INFO, "Budget on track",
                    pct + "% of the " + fmt(budgetMinor, currency) + " budget is spent — "
                        + fmt(remaining, currency) + " remaining."));
            }
        }

        // Category totals (insertion order follows the expense list, so the
        // tie-break below is deterministic for a given input).
        Map<String, Long> byCategory = new LinkedHashMap<>();
        for (ExpenseFact e : expenses) {
            if (e.categoryCode() == null) continue;
            byCategory.merge(e.categoryCode(), e.amountMinor(), Long::sum);
        }

        // 2. Category concentration.
        if (totalSpent > 0 && byCategory.size() >= 2) {
            Map.Entry<String, Long> top = topEntry(byCategory);
            long share = Math.round(top.getValue() * 100.0 / totalSpent);
            if (share >= 40) {
                String name = categoryNames.getOrDefault(top.getKey(), top.getKey());
                out.add(new Insight("CATEGORY_CONCENTRATION",
                    share >= 60 ? Insight.WARNING : Insight.INFO,
                    "Spending concentrated in " + name,
                    name + " accounts for " + share + "% of spend ("
                        + fmt(top.getValue(), currency) + ")."));
            }
        }

        // 3. Possible duplicates: same amount + same day + same category.
        Map<String, Integer> groupCounts = new LinkedHashMap<>();
        Map<String, ExpenseFact> groupSample = new HashMap<>();
        for (ExpenseFact e : expenses) {
            String key = e.amountMinor() + "|"
                + (e.day() == null ? "" : e.day()) + "|"
                + (e.categoryCode() == null ? "" : e.categoryCode());
            groupCounts.merge(key, 1, Integer::sum);
            groupSample.putIfAbsent(key, e);
        }
        int dupReported = 0;
        for (Map.Entry<String, Integer> g : groupCounts.entrySet()) {
            if (g.getValue() < 2 || dupReported >= 2) continue;
            ExpenseFact e = groupSample.get(g.getKey());
            String name = categoryNames.getOrDefault(
                e.categoryCode(),
                e.categoryCode() == null ? "uncategorised" : e.categoryCode());
            out.add(new Insight("POSSIBLE_DUPLICATE", Insight.WARNING, "Possible duplicate",
                g.getValue() + " expenses of " + fmt(e.amountMinor(), currency)
                    + (e.day() == null ? "" : " on " + e.day())
                    + " in " + name + " — check for a double entry."));
            dupReported++;
        }

        // 4. Top spender.
        if (totalSpent > 0) {
            Map<UUID, Long> byUser = new LinkedHashMap<>();
            for (ExpenseFact e : expenses) {
                if (e.userId() == null) continue;
                byUser.merge(e.userId(), e.amountMinor(), Long::sum);
            }
            if (byUser.size() >= 2) {
                Map.Entry<UUID, Long> top = topEntry(byUser);
                long share = Math.round(top.getValue() * 100.0 / totalSpent);
                String name = userNames.getOrDefault(top.getKey(), "A team member");
                out.add(new Insight("TOP_SPENDER", Insight.INFO, "Highest spender",
                    name + " has the highest spend at " + fmt(top.getValue(), currency)
                        + " (" + share + "% of the total)."));
            }
        }

        String narrative = buildNarrative(
            tripName, currency, budgetMinor, totalSpent, count, byCategory, categoryNames);
        return new TripInsightsDto(narrative, out);
    }

    private String buildNarrative(
        String tripName,
        String currency,
        long budgetMinor,
        long totalSpent,
        int count,
        Map<String, Long> byCategory,
        Map<String, String> categoryNames
    ) {
        String name = (tripName == null || tripName.isBlank()) ? "This trip" : tripName;
        if (count == 0) {
            return name + " has no recorded expenses yet.";
        }
        StringBuilder sb = new StringBuilder();
        sb.append(name).append(" has recorded ").append(count)
            .append(count == 1 ? " expense" : " expenses")
            .append(" totalling ").append(fmt(totalSpent, currency));
        if (budgetMinor > 0) {
            long pct = Math.round(totalSpent * 100.0 / budgetMinor);
            sb.append(", ").append(pct).append("% of the ")
                .append(fmt(budgetMinor, currency)).append(" budget");
        }
        sb.append(".");
        if (!byCategory.isEmpty() && totalSpent > 0) {
            Map.Entry<String, Long> top = topEntry(byCategory);
            long share = Math.round(top.getValue() * 100.0 / totalSpent);
            String catName = categoryNames.getOrDefault(top.getKey(), top.getKey());
            sb.append(" ").append(catName)
                .append(" is the largest category at ").append(share).append("%.");
        }
        if (budgetMinor > 0) {
            long remaining = budgetMinor - totalSpent;
            if (remaining < 0) {
                sb.append(" The budget is exceeded by ")
                    .append(fmt(-remaining, currency)).append(".");
            } else {
                sb.append(" ").append(fmt(remaining, currency)).append(" remains.");
            }
        }
        return sb.toString();
    }

    /** Highest-valued entry; ties keep the first one encountered (the map is
     *  iterated in insertion order). */
    private static <K> Map.Entry<K, Long> topEntry(Map<K, Long> m) {
        Map.Entry<K, Long> best = null;
        for (Map.Entry<K, Long> e : m.entrySet()) {
            if (best == null || e.getValue() > best.getValue()) {
                best = e;
            }
        }
        return best;
    }

    /** Format minor units as "AED 1,234.00" — currency code first per the
     *  design (CLAUDE.md §8). Handles 0/2/3-decimal currencies. */
    static String fmt(long minor, String ccy) {
        int dec = decimals(ccy);
        boolean neg = minor < 0;
        long abs = Math.abs(minor);
        long div = 1;
        for (int i = 0; i < dec; i++) div *= 10;
        long major = abs / div;
        long frac = abs % div;
        StringBuilder sb = new StringBuilder();
        sb.append(ccy == null ? "" : ccy).append(' ');
        if (neg) sb.append('-');
        sb.append(String.format(Locale.US, "%,d", major));
        if (dec > 0) {
            sb.append('.');
            String fs = Long.toString(frac);
            while (fs.length() < dec) fs = "0" + fs;
            sb.append(fs);
        }
        return sb.toString();
    }

    private static int decimals(String ccy) {
        if (ccy == null) return 2;
        switch (ccy.toUpperCase(Locale.ROOT)) {
            case "BHD": case "KWD": case "OMR": case "JOD": case "TND": case "LYD":
                return 3;
            case "JPY": case "KRW": case "VND":
                return 0;
            default:
                return 2;
        }
    }
}
