import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";
import uploadAndCreateDraft from "@salesforce/apex/PdfOpportunityController.uploadAndCreateDraft";
import compareAndCreateQuotes from "@salesforce/apex/PdfOpportunityController.compareAndCreateQuotes";

const MAX_SIZE = 4500000; // ~4.5 MB por archivo: límite práctico para enviar base64 a Apex
const MIN_FILES = 2;
const MIN_PREFIX_LENGTH = 3;

export default class PdfOpportunityCreator extends NavigationMixin(
  LightningElement
) {
  files = [];
  isProcessing = false;
  statusMessage = "";

  result;
  error = "";
  prefixWarning = "";
  glosarioOpen = false;

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

  get successBanner() {
    if (!this.result) {
      return "";
    }
    const vehiculo = this.result.vehiculo || "el vehículo";
    const cliente = this.result.cliente || "cliente sin nombre";
    const n = (this.result.quotes || []).length;
    return `Oportunidad creada para ${vehiculo} (${cliente}) con ${n} cotizaciones`;
  }

  get ganadoras() {
    const r = this.result && this.result.recomendacion;
    if (!r || !Array.isArray(r.ganadoras)) {
      return [];
    }
    return r.ganadoras.map((g, i) => ({
      key: "g" + i,
      titulo: `${g.nombre || "Sin nombre"} — ${g.etiqueta || ""}`.trim(),
      porque: g.porque || "",
      aCambio: g.a_cambio || ""
    }));
  }

  get enPocasPalabras() {
    return (
      (this.result &&
        this.result.recomendacion &&
        this.result.recomendacion.en_pocas_palabras) ||
      ""
    );
  }

  get hasRecomendacion() {
    return this.ganadoras.length > 0 || !!this.enPocasPalabras;
  }

  get quoteCards() {
    const quotes = (this.result && this.result.quotes) || [];
    return quotes.map((q, i) => {
      const title = (q.aseguradora && q.aseguradora.trim()) || q.name || `Cotización ${i + 1}`;
      const rows = [
        { key: "p", label: "Prima anual", value: formatCurrency(q.primaAnual) },
        { key: "s", label: "Suma asegurada", value: formatCurrency(q.sumaAsegurada) },
        {
          key: "tv",
          label: "Tipo de valor",
          value: q.tipoValor || "—",
          isBadge: true
        },
        {
          key: "dd",
          label: "Deducible Daños",
          value: formatDeducible(q.deducibleDanosPct, q.deducibleDanosMxn)
        },
        {
          key: "dr",
          label: "Deducible Robo",
          value: formatDeducible(q.deducibleRoboPct, q.deducibleRoboMxn)
        },
        { key: "rc", label: "RC", value: formatCurrency(q.responsabilidadCivil) },
        { key: "gm", label: "Gastos médicos", value: formatCurrency(q.gastosMedicos) },
        { key: "vc", label: "Vida conductor", value: formatCurrency(q.vidaConductor) }
      ];
      const chips = [
        { key: "ch_cri", label: "Cristales", on: !!q.cristales },
        { key: "ch_av", label: "Asistencia vial", on: !!q.asistenciaVial },
        { key: "ch_dj", label: "Defensa jurídica", on: !!q.defensaJuridica },
        { key: "ch_rce", label: "RC extranjero", on: !!q.rcExtranjero }
      ].map((c) => ({
        ...c,
        cls: c.on ? "chip chip_on" : "chip chip_off"
      }));
      return {
        key: q.id || "q" + i,
        title,
        rows,
        chips,
        notas: (q.notas && q.notas.trim()) || ""
      };
    });
  }

  get guiaFrecuencia() {
    const g =
      (this.result &&
        this.result.recomendacion &&
        this.result.recomendacion.guia_frecuencia) ||
      [];
    return g.map((row, i) => ({
      key: "gf" + i,
      riesgo: row.riesgo || "",
      frecuencia: row.frecuencia || "",
      gana: row.gana || "",
      detalle: row.detalle || ""
    }));
  }

  get hasGuia() {
    return this.guiaFrecuencia.length > 0;
  }

  get hasComparativoPdf() {
    return !!(this.result && this.result.comparativoPdfId);
  }

  get glosario() {
    const g = (this.result && this.result.glosario) || [];
    return g.map((item, i) => ({
      key: "gl" + i,
      termino: item.termino || "",
      definicion: item.definicion || ""
    }));
  }

  get hasGlosario() {
    return this.glosario.length > 0;
  }

  get glosarioToggleLabel() {
    return this.glosarioOpen ? "Ocultar glosario" : "Ver glosario";
  }

  get aviso() {
    return (this.result && this.result.aviso) || "";
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
        "Comparando cotizaciones con IA y creando los Quotes…";
      const res = await compareAndCreateQuotes({
        opportunityId: draft.opportunityId,
        contentDocumentIds: draft.contentDocumentIds
      });

      this.result = res;
      const n = (res.quotes || []).length;
      this.showToast(
        "Oportunidad creada",
        `Se crearon ${n} cotizaciones para "${res.vehiculo || res.opportunityName || "la oportunidad"}".`,
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

  handleOpenComparativoPdf() {
    if (!this.hasComparativoPdf) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__namedPage",
      attributes: { pageName: "filePreview" },
      state: { selectedRecordId: this.result.comparativoPdfId }
    });
  }

  handleToggleGlosario() {
    this.glosarioOpen = !this.glosarioOpen;
  }

  handleReset() {
    this.files = [];
    this.result = undefined;
    this.error = "";
    this.prefixWarning = "";
    this.glosarioOpen = false;
    const input = this.template.querySelector('lightning-input[type="file"]');
    if (input) {
      input.value = null;
    }
  }

  readAsBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const base64 = reader.result.split(",")[1];
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

function formatCurrency(v) {
  if (v === null || v === undefined || v === "") {
    return "—";
  }
  const n = Number(v);
  if (Number.isNaN(n)) {
    return String(v);
  }
  try {
    return new Intl.NumberFormat("es-MX", {
      style: "currency",
      currency: "MXN",
      maximumFractionDigits: 0
    }).format(n);
  } catch (e) {
    return "$" + n.toFixed(0);
  }
}

function formatDeducible(pct, mxn) {
  const hasPct = pct !== null && pct !== undefined && pct !== "";
  const hasMxn = mxn !== null && mxn !== undefined && mxn !== "";
  if (!hasPct && !hasMxn) {
    return "—";
  }
  const pctStr = hasPct ? `${Number(pct)}%` : "—";
  const mxnStr = hasMxn ? formatCurrency(mxn) : "—";
  return `${pctStr} — ${mxnStr}`;
}

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
  while (prefix.length > 0 && "._- ".includes(prefix.charAt(prefix.length - 1))) {
    prefix = prefix.substring(0, prefix.length - 1);
  }
  return prefix.length >= MIN_PREFIX_LENGTH ? prefix : "";
}