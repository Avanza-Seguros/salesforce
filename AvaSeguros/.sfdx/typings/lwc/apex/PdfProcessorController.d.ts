declare module "@salesforce/apex/PdfProcessorController.processPdfData" {
  export default function processPdfData(param: {pdfData: any}): Promise<any>;
}
declare module "@salesforce/apex/PdfProcessorController.getPolicyIds" {
  export default function getPolicyIds(param: {policyNumbers: any, certificateNumbers: any}): Promise<any>;
}
declare module "@salesforce/apex/PdfProcessorController.savePdfFile" {
  export default function savePdfFile(param: {base64Data: any, fileName: any, parentId: any, certificate: any, policyNumber: any}): Promise<any>;
}
declare module "@salesforce/apex/PdfProcessorController.findPolicies" {
  export default function findPolicies(param: {searchTerm: any}): Promise<any>;
}
declare module "@salesforce/apex/PdfProcessorController.findItemsForPolicy" {
  export default function findItemsForPolicy(param: {policyId: any, certificate: any}): Promise<any>;
}
declare module "@salesforce/apex/PdfProcessorController.isTitular" {
  export default function isTitular(param: {itemCaseId: any}): Promise<any>;
}
