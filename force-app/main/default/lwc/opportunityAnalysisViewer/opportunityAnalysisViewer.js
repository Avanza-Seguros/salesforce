import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import DESCRIPTION_FIELD from "@salesforce/schema/Opportunity.Description";

// Marcadores del formato actual (multi-documento)
const RESUMEN_EJEC_TITLE = "RESUMEN EJECUTIVO";
const COMPARATIVO_TITLE = "COMPARATIVO";

// Marcadores legacy (un solo documento)
const DATOS_MARKER = "=== DATOS EXTRAÍDOS POR IA ===";
const ANALISIS_MARKER = "=== ANÁLISIS COMPLETO (IA) ===";

// Iconos por etiqueta de dato clave
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

// Iconos por número de sección del análisis
const SECTION_ICONS = {
  1: "utility:file",
  2: "utility:description",
  3: "utility:key",
  4: "utility:opportunity",
  5: "utility:warning",
  6: "utility:task"
};

export default class OpportunityAnalysisViewer extends LightningElement {
  @api recordId;

  description = "";
  loaded = false;
  errorMsg = "";

  // Legado (un doc)
  headerTipo = "";
  headerCliente = "";
  summary = "";
  keyData = [];
  sections = [];

  // Nuevo formato (multi-doc)
  executiveSummary = "";
  comparisonTable = null;
  docAnalyses = [];

  @wire(getRecord, { recordId: "$recordId", fields: [DESCRIPTION_FIELD] })
  wiredOpp({ data, error }) {
    if (data) {
      this.description = getFieldValue(data, DESCRIPTION_FIELD) || "";
      this.parse();
      this.loaded = true;
    } else if (error) {
      this.errorMsg = "No se pudo cargar la descripción de la oportunidad.";
      this.loaded = true;
    }
  }

  get hasContent() {
    return (
      this.keyData.length > 0 ||
      this.sections.length > 0 ||
      !!this.executiveSummary ||
      !!this.comparisonTable ||
      this.docAnalyses.length > 0
    );
  }

  get showEmptyState() {
    return this.loaded && !this.hasContent;
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

    // El nuevo formato usa bloques delimitados por "=== <título> ===".
    // El legacy también, pero con títulos fijos. Procesamos por bloques y
    // routamos según el título.
    const blocks = splitIntoBlocks(text);
    if (blocks.length === 0) {
      // No hay marcadores: tratar todo como análisis libre.
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
        // Cualquier otro título: bloque de análisis de un documento.
        docBlocks.push(b);
      }
    }

    // Si hay datos extraídos del legado se vuelcan a las tiles.
    if (legacyDatos) {
      this.parseKeyData(legacyDatos);
    }
    if (legacyAnalisis) {
      this.parseSections(legacyAnalisis);
    }

    // Análisis por documento (nuevo formato).
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

    // Extraer cliente del resumen ejecutivo para el hero si no vino por legado.
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

    const headerCells = cellsOf(lines[0]); // ["Campo", "doc1", "doc2", ...]
    // lines[1] es el separador "| --- | --- |..."
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

// Divide el texto en bloques delimitados por líneas "=== Título ===".
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