public with sharing class BanxicoQueueable implements Queueable, Database.AllowsCallouts {

    private Boolean isHistorical;
    private Date fromDate;
    private Date toDate;
    private Integer chunkDays;

    public BanxicoQueueable() {
        this.isHistorical = false;
    }

    public BanxicoQueueable(Date fromDate, Date toDate, Integer chunkDays) {
        this.isHistorical = true;
        this.fromDate = fromDate;
        this.toDate = toDate;
        this.chunkDays = (chunkDays == null || chunkDays <= 0) ? 30 : chunkDays;
    }

    public void execute(QueueableContext context) {

        if (!isHistorical) {
            BanxicoExchangeRateService.fetchLatestRates();
            return;
        }

        if (fromDate == null || toDate == null) {
            return;
        }
        if (fromDate > toDate) {
            return;
        }
        Integer effectiveChunkDays = (chunkDays == null || chunkDays <= 0) ? 30 : chunkDays;

        Date chunkEnd = fromDate.addDays(effectiveChunkDays - 1);
        if (chunkEnd > toDate){
            chunkEnd = toDate;
        }
        if (chunkEnd < fromDate) {
            return;
        }
        BanxicoExchangeRateService.fetchHistoricalRates(fromDate, chunkEnd);

        Date nextStart = chunkEnd.addDays(1);

        if (nextStart <= toDate && nextStart > fromDate) {
            System.enqueueJob(new BanxicoQueueable(nextStart, toDate, effectiveChunkDays));
        }
    }
}