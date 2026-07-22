import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { NavigationMixin } from "lightning/navigation";
import DESCRIPTION_FIELD from "@salesforce/schema/Opportunity.Description";
import COMPARATIVO_FIELD from "@salesforce/schema/Opportunity.Descripcion__c";
import getQuotesByOpportunity from "@salesforce/apex/OpportunityQuotesController.getQuotesByOpportunity";
import getComparativoLinks from "@salesforce/apex/OpportunityQuotesController.getComparativoLinks";

const RESUMEN_EJEC_TITLE = "RESUMEN EJECUTIVO";
const COMPARATIVO_TITLE = "COMPARATIVO";

const DATA_ICONS = {
  "Tipo de documento": "utility:file",
  Cliente: "utility:user",
  Aseguradora: "utility:company",
  Ramo: "utility:category",
  "No. Póliza": "utility:contract",
  "No. Cotización": "utility:quote",
  Prima: "utility:moneybag",
  "Suma asegurada": "utility:shield",
  Moneda: "utility:currency",
  Vigencia: "utility:event",
  Correo: "utility:email",
  Teléfono: "utility:call"
};

const SECTION_ICONS = {
  1: "utility:file",
  2: "utility:description",
  3: "utility:key",
  4: "utility:opportunity",
  5: "utility:warning",
  6: "utility:task"
};

export default class OpportunityAnalysisViewer extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  description = "";
  loaded = false;
  errorMsg = "";

  headerTipo = "";
  headerCliente = "";
  summary = "";
  keyData = [];
  sections = [];

  executiveSummary = "";
  comparisonTable = null;
  docAnalyses = [];

  rawQuotes = [];
  comparativoPdfId = null;
  comparativoTitle = "";
  comparativoHtml = "";
  _comparativoDirty = false;

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [DESCRIPTION_FIELD, COMPARATIVO_FIELD]
  })
  wiredOpp({ data, error }) {
    if (data) {
      this.description = getFieldValue(data, DESCRIPTION_FIELD) || "";
      console.log("description::: " + this.description); 
      this.parse();
      this.comparativoHtml = getFieldValue(data, COMPARATIVO_FIELD) || "";
      this._comparativoDirty = true;
      this.loaded = true;
    } else if (error) {
      this.errorMsg = "No se pudo cargar la descripción de la oportunidad.";
      this.loaded = true;
    }
  }

  get hasComparativoHtml() {
    return !!(this.comparativoHtml && this.comparativoHtml.trim());
  }

  // Inyecta el HTML de la IA en un div con lwc:dom="manual". Se evita el iframe
  // (srcdoc y blob: los bloquea la CSP de Lightning y causaban "Script error").
  renderedCallback() {
    if (!this._comparativoDirty) {
      return;
    }
    const host = this.template.querySelector(".comparativo-ia__host");
    if (!host) {
      return;
    }
    this._comparativoDirty = false;
    try {
      host.innerHTML = this.comparativoHtml || "";
    } catch (e) {
      // No romper el componente si el HTML no se puede inyectar.
    }
  }

  @wire(getQuotesByOpportunity, { opportunityId: "$recordId" })
  wiredQuotes({ data, error }) {
    if (data) {
      this.rawQuotes = data;
    } else if (error) {
      this.rawQuotes = [];
    }
  }

  @wire(getComparativoLinks, { opportunityId: "$recordId" })
  wiredLinks({ data, error }) {
    if (data && data.length) {
      this.comparativoPdfId = data[0].contentDocumentId;
      this.comparativoTitle = data[0].title;
    } else if (error) {
      this.comparativoPdfId = null;
    }
  }

  get hasContent() {
    return (
      this.keyData.length > 0 ||
      this.sections.length > 0 ||
      !!this.executiveSummary ||
      !!this.comparisonTable ||
      this.docAnalyses.length > 0 ||
      this.quoteTiles.length > 0 ||
      !!this.comparativoPdfId ||
      this.hasComparativoHtml
    );
  }

  get showEmptyState() {
    return this.loaded && !this.hasContent;
  }

  get quoteTiles() {
    if (!this.rawQuotes || this.rawQuotes.length === 0) {
      return [];
    }
    return this.rawQuotes.map((q, i) => {
      const title = (q.aseguradora && q.aseguradora.trim()) || q.name || `Cotización ${i + 1}`;
      const rows = [
        { key: "p", label: "Prima anual", value: formatCurrency(q.primaAnual) },
        { key: "s", label: "Suma asegurada", value: formatCurrency(q.sumaAsegurada) },
        { key: "tv", label: "Tipo de valor", value: q.tipoValor || "—", isBadge: true },
        {
          key: "dd",
          label: "Deducible Daños",
          value: formatDeducible(q.deducibleDanosPct, q.deducibleDanosMxn)
        },
        {
          key: "dr",
          label: "Deducible Robo",
          value: formatDeducible(q.deducibleRoboPct, q.deducibleRoboMxn)
        }
      ];
      return {
        key: q.id || "qt" + i,
        id: q.id,
        title,
        rows
      };
    });
  }

  get hasQuotes() {
    return this.quoteTiles.length > 0;
  }

  // Matriz comparativa (cobertura × aseguradora) construida con las coberturas
  // reales de cada cotización. Funciona para cualquier ramo (Autos, GMM, etc.).
  get coverageMatrix() {
    const quotes = this.rawQuotes || [];
    if (quotes.length === 0) {
      return null;
    }
    // Columnas: una por cotización (aseguradora + prima), ya ordenadas por prima.
    const cols = quotes.map((q, i) => ({
      key: q.id || "col" + i,
      aseguradora:
        (q.aseguradora && q.aseguradora.trim()) || q.name || `Cotización ${i + 1}`,
      prima: formatCurrency(q.primaAnual)
    }));
    // Unión de nombres de cobertura (en orden de aparición, sin repetir).
    const order = [];
    const seen = new Set();
    quotes.forEach((q) => {
      (q.coberturas || []).forEach((nm) => {
        const n = (nm || "").trim();
        const k = n.toLowerCase();
        if (n && !seen.has(k)) {
          seen.add(k);
          order.push(n);
        }
      });
    });
    if (order.length === 0) {
      return null;
    }
    const sets = quotes.map(
      (q) => new Set((q.coberturas || []).map((x) => (x || "").trim().toLowerCase()))
    );
    const rows = order.map((cov, ri) => {
      const cells = sets.map((s, ci) => {
        const has = s.has(cov.toLowerCase());
        return {
          key: "r" + ri + "c" + ci,
          has,
          value: has ? "Sí" : "—",
          cls: has ? "cov-cell cov-yes" : "cov-cell cov-no"
        };
      });
      const yes = cells.filter((c) => c.has).length;
      const partial = yes > 0 && yes < cells.length;
      return {
        key: "cov" + ri,
        label: cov,
        cells,
        rowClass: partial ? "cov-row cov-diff" : "cov-row"
      };
    });
    return { cols, rows, total: order.length };
  }

  get hasCoverageMatrix() {
    return this.coverageMatrix !== null;
  }

  get hasComparativo() {
    return !!this.comparativoPdfId;
  }

  handleOpenComparativo() {
    if (!this.comparativoPdfId) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__namedPage",
      attributes: { pageName: "filePreview" },
      state: { selectedRecordId: this.comparativoPdfId }
    });
  }

  handleOpenQuote(event) {
    const id = event.currentTarget.dataset.id;
    if (!id) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: id, objectApiName: "Quote", actionName: "view" }
    });
  }

  parse() {
    this.keyData = [];
    this.sections = [];
    this.summary = "";
    this.headerTipo = "";
    this.headerCliente = "";
    this.executiveSummary = "";
    this.comparisonTable = null;
    this.docAnalyses = [];

    const text = this.description || "";
    if (!text.trim()) {
      return;
    }

    const blocks = splitIntoBlocks(text);
    if (blocks.length === 0) {
      this.parseSections(text);
      return;
    }

    let legacyDatos = "";
    let legacyAnalisis = "";
    const docBlocks = [];

    for (const b of blocks) {
      const upper = b.title.toUpperCase();
      if (upper.includes(RESUMEN_EJEC_TITLE)) {
        this.executiveSummary = b.body.trim();
      } else if (upper.includes(COMPARATIVO_TITLE)) {
        this.comparisonTable = this.parseMarkdownTable(b.body);
      } else if (upper.includes("DATOS EXTRAÍDOS")) {
        legacyDatos = b.body;
      } else if (upper.includes("ANÁLISIS COMPLETO")) {
        legacyAnalisis = b.body;
      } else if (b.title) {
        docBlocks.push(b);
      }
    }

    if (legacyDatos) {
      this.parseKeyData(legacyDatos);
    }
    if (legacyAnalisis) {
      this.parseSections(legacyAnalisis);
    }

    docBlocks.forEach((b, i) => {
      const items = this.parseBody(b.body.split("\n"), "doc" + i);
      const risks = this.detectRisks(items);
      this.docAnalyses.push({
        key: "doc" + i,
        title: b.title,
        icon: "doctype:pdf",
        contentItems: risks.length ? [] : items,
        riskItems: risks,
        hasRisks: risks.length > 0
      });
    });

    if (!this.headerCliente && this.executiveSummary) {
      const m = this.executiveSummary.match(
        /Se analizaron \d+ documentos para (.+?)(?:\s*\(ramo\s+.+?\))?\./
      );
      if (m) {
        this.headerCliente = m[1].trim();
      }
      const r = this.executiveSummary.match(/\(ramo\s+(.+?)\)/);
      if (r) {
        this.headerTipo = "Ramo " + r[1].trim();
      }
    }
  }

  parseMarkdownTable(block) {
    if (!block) {
      return null;
    }
    const lines = block
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.startsWith("|") && l.endsWith("|"));
    if (lines.length < 3) {
      return null;
    }
    const cellsOf = (line) =>
      line
        .slice(1, -1)
        .split("|")
        .map((s) => s.trim());

    const headerCells = cellsOf(lines[0]);
    const dataLines = lines.slice(2).filter((l) => !/^\|\s*-+/.test(l));

    const headers = headerCells.slice(1).map((h, i) => ({
      key: "h" + i,
      label: h
    }));

    const rows = dataLines
      .map((line, ri) => {
        const cells = cellsOf(line);
        if (cells.length < 2) {
          return null;
        }
        const label = cells[0];
        const values = cells.slice(1);
        const nonEmpty = values.filter((v) => v && v !== "—");
        const isDifferent = new Set(nonEmpty).size > 1;
        const allEmpty = nonEmpty.length === 0;
        if (allEmpty) {
          return null;
        }
        const valueCells = values.map((v, ci) => ({
          key: "c" + ri + "_" + ci,
          value: v || "—",
          cellClass: isDifferent ? "cell diff-cell" : "cell"
        }));
        return {
          key: "r" + ri,
          label,
          cells: valueCells,
          rowClass: isDifferent ? "diff-row" : ""
        };
      })
      .filter((r) => r !== null);

    if (rows.length === 0) {
      return null;
    }
    return { headers, rows };
  }

  parseKeyData(block) {
    if (!block) {
      return;
    }
    block.split("\n").forEach((line) => {
      const t = line.trim();
      if (!t) {
        return;
      }
      const ci = t.indexOf(":");
      if (ci < 0) {
        return;
      }
      const label = t.substring(0, ci).trim();
      const value = t.substring(ci + 1).trim();
      if (label.toLowerCase() === "resumen") {
        this.summary = value;
        return;
      }
      if (!value || value === "—" || value === "— a —") {
        return;
      }
      if (label === "Tipo de documento") {
        this.headerTipo = value;
      }
      if (label === "Cliente") {
        this.headerCliente = value;
      }
      this.keyData.push({
        key: label,
        label,
        value,
        icon: DATA_ICONS[label] || "utility:info"
      });
    });
  }

  parseSections(block) {
    if (!block || !block.trim()) {
      return;
    }
    const headerRe = /^\s*(\d+)[.)-]\s+(.+?)\s*$/;
    const lines = block.split("\n");
    let current = null;
    const pushCurrent = () => {
      if (current) {
        this.finalizeSection(current);
        this.sections.push(current);
      }
    };

    lines.forEach((line) => {
      const m = line.match(headerRe);
      const title = m ? m[2].trim() : "";
      const isHeader = m && title.length <= 60 && title === title.toUpperCase();
      if (isHeader) {
        pushCurrent();
        const num = m[1];
        current = {
          key: "sec" + num + "_" + this.sections.length,
          number: num,
          title,
          icon: SECTION_ICONS[num] || "utility:chevronright",
          isRisk: /RIESGO|OBSERVAC/i.test(title),
          rawLines: []
        };
      } else if (current) {
        current.rawLines.push(line);
      } else if (line.trim()) {
        current = {
          key: "intro",
          number: "",
          title: "RESUMEN",
          icon: "utility:description",
          isRisk: false,
          rawLines: [line]
        };
      }
    });
    pushCurrent();
  }

  finalizeSection(section) {
    if (section.isRisk) {
      section.riskItems = this.parseRisks(section.rawLines);
      section.contentItems = [];
    } else {
      section.riskItems = [];
      section.contentItems = this.parseBody(section.rawLines, section.key);
    }
    delete section.rawLines;
  }

  parseBody(lines, baseKey) {
    const items = [];
    lines.forEach((line, i) => {
      const t = line.trim();
      if (!t) {
        return;
      }
      const isBullet = /^[-•*]\s?/.test(t);
      items.push({
        key: baseKey + "_b" + i,
        text: isBullet ? t.replace(/^[-•*]\s?/, "") : t,
        isBullet,
        cls: isBullet ? "is-bullet" : "is-text"
      });
    });
    return items;
  }

  detectRisks(items) {
    const sevRe = /^(CR[IÍ]TICO|MODERADO|OK)\s*[:.-]?\s*(.*)$/i;
    const risks = [];
    items.forEach((it, idx) => {
      const m = it.text.match(sevRe);
      if (!m) {
        return;
      }
      const raw = m[1].toUpperCase();
      let severity = "ok";
      let icon = "utility:success";
      let cls = "risk risk_ok";
      let badge = "OK";
      if (raw.startsWith("CR")) {
        severity = "critico";
        icon = "utility:error";
        cls = "risk risk_critico";
        badge = "CRÍTICO";
      } else if (raw.startsWith("MOD")) {
        severity = "moderado";
        icon = "utility:warning";
        cls = "risk risk_moderado";
        badge = "MODERADO";
      }
      risks.push({
        key: "risk_" + idx,
        severity,
        icon,
        cls,
        badge,
        text: m[2].trim()
      });
    });
    return risks;
  }

  parseRisks(lines) {
    const items = [];
    const sevRe = /^[-•*\s]*(CR[IÍ]TICO|MODERADO|OK)\s*[:.-]?\s*(.*)$/i;
    let idx = 0;
    lines.forEach((line) => {
      const t = line.trim();
      if (!t) {
        return;
      }
      const m = t.match(sevRe);
      if (m) {
        const raw = m[1].toUpperCase();
        let severity = "ok";
        let icon = "utility:success";
        let cls = "risk risk_ok";
        let badge = "OK";
        if (raw.startsWith("CR")) {
          severity = "critico";
          icon = "utility:error";
          cls = "risk risk_critico";
          badge = "CRÍTICO";
        } else if (raw.startsWith("MOD")) {
          severity = "moderado";
          icon = "utility:warning";
          cls = "risk risk_moderado";
          badge = "MODERADO";
        }
        items.push({
          key: "risk_" + idx++,
          severity,
          icon,
          cls,
          badge,
          text: m[2].trim()
        });
      } else if (items.length) {
        items[items.length - 1].text += " " + t;
      } else {
        items.push({
          key: "risk_" + idx++,
          severity: "info",
          icon: "utility:info",
          cls: "risk risk_info",
          badge: "NOTA",
          text: t.replace(/^[-•*]\s?/, "")
        });
      }
    });
    return items;
  }
}

function splitIntoBlocks(text) {
  const blocks = [];
  const lines = text.split("\n");
  const headerRe = /^===\s*(.+?)\s*===\s*$/;
  let current = null;
  for (const line of lines) {
    const m = line.match(headerRe);
    if (m) {
      if (current) {
        blocks.push(current);
      }
      current = { title: m[1].trim(), body: "" };
    } else if (current) {
      current.body += line + "\n";
    }
  }
  if (current) {
    blocks.push(current);
  }
  return blocks;
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