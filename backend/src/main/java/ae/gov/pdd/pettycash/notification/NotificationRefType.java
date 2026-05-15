package ae.gov.pdd.pettycash.notification;

/**
 * Discriminator for {@link Notification#getRefId()}. Used when a respond on
 * an allocation / transfer needs to flip every notification that pointed at
 * the same row to {@link NotificationState#ACTED}.
 */
public enum NotificationRefType { ALLOCATION, TRANSFER, TRIP, EXPENSE }
