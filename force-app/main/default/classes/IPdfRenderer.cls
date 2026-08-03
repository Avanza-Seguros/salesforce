public interface IPdfRenderer {
  Blob renderToPdf(String htmlContent, String fileName);
}