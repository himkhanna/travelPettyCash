package ae.gov.pdd.pettycash.common;

public class NotFoundException extends RuntimeException {
    public NotFoundException() { super("Not found"); }
    public NotFoundException(String msg) { super(msg); }
}
