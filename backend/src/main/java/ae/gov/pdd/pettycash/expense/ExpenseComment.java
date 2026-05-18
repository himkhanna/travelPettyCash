package ae.gov.pdd.pettycash.expense;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;

@Entity
@Table(name = "expense_comments")
public class ExpenseComment {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "expense_id", nullable = false)
    private UUID expenseId;

    @Column(name = "author_id", nullable = false)
    private UUID authorId;

    @Column(name = "body", nullable = false, length = 2000)
    private String body;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "deleted_at")
    private Instant deletedAt;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(
        name = "expense_comment_mentions",
        joinColumns = @JoinColumn(name = "comment_id")
    )
    @Column(name = "user_id", nullable = false)
    private Set<UUID> mentionedUserIds = new LinkedHashSet<>();

    protected ExpenseComment() {
        // JPA
    }

    public ExpenseComment(
        UUID id,
        UUID expenseId,
        UUID authorId,
        String body,
        Set<UUID> mentionedUserIds
    ) {
        this.id = id;
        this.expenseId = expenseId;
        this.authorId = authorId;
        this.body = body;
        if (mentionedUserIds != null) {
            this.mentionedUserIds = new LinkedHashSet<>(mentionedUserIds);
        }
    }

    public UUID getId() { return id; }
    public UUID getExpenseId() { return expenseId; }
    public UUID getAuthorId() { return authorId; }
    public String getBody() { return body; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getDeletedAt() { return deletedAt; }
    public Set<UUID> getMentionedUserIds() { return mentionedUserIds; }
}
