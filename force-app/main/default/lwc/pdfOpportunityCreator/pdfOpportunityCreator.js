import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";
import uploadAndCreateDraft from "@salesforce/apex/PdfOpportunityController.uploadAndCreateDraft";
import analyzeAndPopulate from "@salesforce/apex/PdfOpportunityController.analyzeAndPopulate";

const MAX_SIZE = 4500000; // ~4.5 MB por archivo: límite práctico para enviar base64 a Apex
const MIN_FILES = 2;
const MIN_PREFIX_LENGTH = 3;

export default class PdfOpportunityCreator extends NavigationMixin(
  LightningElement
) {
  files = []; // array de objetos File seleccionados
  isProcessing = false;
  statusMessage = "";

  // Resultado
  result; // { opportunityId, opportunityName, accountId, analysis, data }
  error = "";
  prefixWarning = "";

  get showUploadStep() {
    return !this.isProcessing && !this.hasResult;
  }

  get hasFiles() {
    return this.files && this.files.length > 0;
  }

  get fileList() {
    return this.files.map((f) => ({ name: f.name }));
  }

  get sharedPrefix() {
    if (!this.hasFiles || this.files.length < MIN_FILES) {
      return "";
    }
    return computeSharedPrefix(this.files.map((f) => f.name));
  }

  get continueDisabled() {
    if (this.isProcessing) {
      return true;
    }
    if (!this.hasFiles || this.files.length < MIN_FILES) {
      return true;
    }
    return !this.sharedPrefix;
  }

  get hasResult() {
    return !!this.result;
  }

  get comparisonTable() {
    const docs = this.result && this.result.documents;
    if (!docs || docs.length < 2) {
      return null;
    }
    const fields = [
      { key: "tipoDocumento", label: "Tipo" },
      { key: "nombreCliente", label: "Cliente" },
      { key: "aseguradora", label: "Aseguradora" },
      { key: "ramo", label: "Ramo" },
      { key: "numeroPoliza", label: "No. Póliza" },
      { key: "numeroCotizacion", label: "No. Cotización" },
      { key: "prima", label: "Prima", numeric: true },
      { key: "sumaAsegurada", label: "Suma asegurada", numeric: true },
      { key: "moneda", label: "Moneda" },
      { key: "vigenciaInicio", label: "Vigencia inicio" },
      { key: "vigenciaFin", label: "Vigencia fin" },
      { key: "correoCliente", label: "Correo" },
      { key: "telefonoCliente", label: "Teléfono" }
    ];
    const headers = docs.map((d, i) => ({
      key: "h" + i,
      label: d.title || "Documento " + (i + 1)
    }));
    const rows = fields
      .map((f) => {
        const rawValues = docs.map((d) =>
          d.data && d.data[f.key] !== null && d.data[f.key] !== undefined
            ? String(d.data[f.key])
            : ""
        );
        const allEmpty = rawValues.every((v) => v === "");
        if (allEmpty) {
          return null;
        }
        const nonEmpty = rawValues.filter((v) => v !== "");
        const isDifferent = new Set(nonEmpty).size > 1;
        const baseCellClass = f.numeric ? "cell numeric" : "cell";
        const cells = rawValues.map((v, i) => ({
          key: "c" + i + "_" + f.key,
          value: v === "" ? "—" : v,
          cellClass: isDifferent
            ? baseCellClass + " diff-cell"
            : baseCellClass
        }));
        return {
          key: f.key,
          label: f.label,
          cells,
          rowClass: isDifferent ? "diff-row" : ""
        };
      })
      .filter((r) => r !== null);
    return { headers, rows };
  }

  get docAnalyses() {
    const docs = this.result && this.result.documents;
    if (!docs) {
      return [];
    }
    return docs.map((d, i) => ({
      key: "d" + i,
      title: d.title || "Documento " + (i + 1),
      analysis: d.analysis && d.analysis.trim()
        ? d.analysis
        : "(Sin análisis disponible para este documento.)"
    }));
  }

  get extractedRows() {
    if (!this.result || !this.result.data) {
      return [];
    }
    const d = this.result.data;
    const labels = {
      tipoDocumento: "Tipo de documento",
      nombreCliente: "Cliente",
      aseguradora: "Aseguradora",
      ramo: "Ramo",
      numeroPoliza: "No. Póliza",
      numeroCotizacion: "No. Cotización",
      prima: "Prima",
      sumaAsegurada: "Suma asegurada",
      moneda: "Moneda",
      vigenciaInicio: "Vigencia inicio",
      vigenciaFin: "Vigencia fin",
      correoCliente: "Correo",
      telefonoCliente: "Teléfono"
    };
    return Object.keys(labels)
      .filter((k) => d[k] !== null && d[k] !== undefined && d[k] !== "")
      .map((k) => ({ key: k, label: labels[k], value: String(d[k]) }));
  }

  handleFileChange(event) {
    this.error = "";
    this.prefixWarning = "";
    const selected = Array.from(event.target.files || []);
    if (selected.length === 0) {
      this.files = [];
      return;
    }
    const accepted = [];
    for (const f of selected) {
      if (
        f.type !== "application/pdf" &&
        !f.name.toLowerCase().endsWith(".pdf")
      ) {
        this.showToast(
          "Archivo no válido",
          `"${f.name}" no es un PDF y fue descartado.`,
          "warning"
        );
        continue;
      }
      if (f.size > MAX_SIZE) {
        this.showToast(
          "Archivo muy grande",
          `"${f.name}" supera ~4.5 MB y fue descartado.`,
          "warning"
        );
        continue;
      }
      accepted.push(f);
    }
    this.files = accepted;

    if (this.files.length > 0 && this.files.length < MIN_FILES) {
      this.prefixWarning = `Sube al menos ${MIN_FILES} PDFs para crear la oportunidad.`;
      return;
    }
    if (this.files.length >= MIN_FILES && !this.sharedPrefix) {
      this.prefixWarning =
        "Los nombres de los PDFs no comparten un prefijo común. Renómbralos para que empiecen igual (mín. " +
        MIN_PREFIX_LENGTH +
        " caracteres en común).";
    }
  }

  async handleContinue() {
    if (!this.hasFiles || this.files.length < MIN_FILES) {
      this.showToast(
        "Faltan archivos",
        `Sube al menos ${MIN_FILES} PDFs para continuar.`,
        "error"
      );
      return;
    }
    if (!this.sharedPrefix) {
      this.showToast(
        "Nombres no coinciden",
        "Los PDFs deben compartir un prefijo común en el nombre.",
        "error"
      );
      return;
    }

    this.isProcessing = true;
    this.error = "";
    this.result = undefined;
    try {
      this.statusMessage = "Subiendo documentos…";
      const base64List = await Promise.all(
        this.files.map((f) => this.readAsBase64(f))
      );
      const fileNames = this.files.map((f) => f.name);

      const draft = await uploadAndCreateDraft({
        fileNames,
        base64DataList: base64List
      });

      this.statusMessage =
        "Analizando los PDFs con IA y creando la oportunidad…";
      const res = await analyzeAndPopulate({
        opportunityId: draft.opportunityId,
        contentDocumentIds: draft.contentDocumentIds
      });

      this.result = res;
      this.showToast(
        "Oportunidad creada",
        'Se creó "' +
          (res.opportunityName || "Oportunidad") +
          '" con ' +
          this.files.length +
          " PDFs adjuntos.",
        "success"
      );
    } catch (e) {
      this.error = this.reduceError(e);
      this.showToast("Error", this.error, "error");
    } finally {
      this.isProcessing = false;
      this.statusMessage = "";
    }
  }

  handleOpenOpportunity() {
    if (!this.result || !this.result.opportunityId) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: this.result.opportunityId,
        objectApiName: "Opportunity",
        actionName: "view"
      }
    });
  }

  handleReset() {
    this.files = [];
    this.result = undefined;
    this.error = "";
    this.prefixWarning = "";
    const input = this.template.querySelector('lightning-input[type="file"]');
    if (input) {
      input.value = null;
    }
  }

  readAsBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const base64 = reader.result.split(",")[1]; // quitar el prefijo data:...;base64,
        resolve(base64);
      };
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(file);
    });
  }

  reduceError(e) {
    if (e && e.body && e.body.message) {
      return e.body.message;
    }
    if (e && e.message) {
      return e.message;
    }
    return "Ocurrió un error inesperado durante el análisis.";
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}

// Calcula el prefijo común (case-insensitive) entre nombres de archivo sin extensión.
// Recorta separadores finales y exige al menos MIN_PREFIX_LENGTH caracteres.
function computeSharedPrefix(names) {
  if (!names || names.length === 0) {
    return "";
  }
  const bases = names.map((n) => {
    const dot = n.lastIndexOf(".");
    const base = dot > 0 ? n.substring(0, dot) : n;
    return base.toLowerCase();
  });
  let prefix = bases[0];
  for (let i = 1; i < bases.length; i++) {
    const other = bases[i];
    const max = Math.min(prefix.length, other.length);
    let j = 0;
    while (j < max && prefix.charAt(j) === other.charAt(j)) {
      j++;
    }
    prefix = prefix.substring(0, j);
    if (!prefix) {
      return "";
    }
  }
  // Recortar separadores finales
  while (prefix.length > 0 && "._- ".includes(prefix.charAt(prefix.length - 1))) {
    prefix = prefix.substring(0, prefix.length - 1);
  }
  return prefix.length >= MIN_PREFIX_LENGTH ? prefix : "";
}