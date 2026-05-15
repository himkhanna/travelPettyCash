package ae.gov.pdd.pettycash.chat;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface ChatThreadMemberRepository
    extends JpaRepository<ChatThreadMember, ChatThreadMember.Key> {

    Optional<ChatThreadMember> findByThreadIdAndUserId(UUID threadId, UUID userId);
}
