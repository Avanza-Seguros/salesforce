import { LightningElement, api } from 'lwc';

export default class KpiCard extends LightningElement {
  @api label;
  @api value;
  @api count;
  @api variant;

  get cardClass() {
    return `kpi-card ${this.variant || ''}`.trim();
  }
}