import { LightningElement, api } from 'lwc';
import { loadScript }           from 'lightning/platformResourceLoader';
import chartjs                  from '@salesforce/resourceUrl/chartjs';

function scoreColor(score) {
    if (score >= 75) return '#2e844a';
    if (score >= 60) return '#dd7a01';
    return '#ea001e';
}

export default class OrgHealthScoreGauge extends LightningElement {
    @api score  = null;
    @api grade  = '--';
    @api label  = 'Overall Health Score';
    @api status = '';

    _libLoaded    = false;
    _chart        = null;
    _lastScore    = undefined;
    _lastStatus   = undefined;
    _lastGrade    = undefined;

    connectedCallback() {
        loadScript(this, chartjs)
            .then(() => {
                this._libLoaded = true;
                this._renderChart();
            })
            .catch(err => console.error('Chart.js load error:', err));
    }

    renderedCallback() {
        if (this._libLoaded) {
            this._renderChart();
        }
    }

    disconnectedCallback() {
        if (this._chart) {
            this._chart.destroy();
            this._chart = null;
        }
    }

    _renderChart() {
        // Skip if nothing changed since last draw
        if (
            this.score  === this._lastScore  &&
            this.status === this._lastStatus &&
            this.grade  === this._lastGrade
        ) return;

        const canvas = this.template.querySelector('canvas.gauge-canvas');
        if (!canvas) return;

        const hasScore     = this.score != null;
        const rawScore     = hasScore ? Math.min(100, Math.max(0, this.score)) : 0;
        const inProgress   = this.status === 'In Progress';
        const fillColor    = hasScore ? scoreColor(rawScore) : '#c9d0de';
        const trackColor   = '#e0e5ee';
        const scoreText    = inProgress ? '…' : (hasScore ? String(Math.round(rawScore)) : '--');
        // Show the grade letter only when we have a real letter (A-F); hide when null, '--', or scanning
        const gradeLetter  = (!inProgress && this.grade && this.grade !== '--') ? this.grade : '';
        const gradeColor   = hasScore ? scoreColor(rawScore) : '#706e6b';

        const config = {
            type: 'doughnut',
            data: {
                datasets: [{
                    // Use a tiny floor so a zero-score renders the grey track cleanly
                    data: [Math.max(rawScore, 0), 100 - Math.max(rawScore, 0)],
                    backgroundColor: [fillColor, trackColor],
                    borderWidth: 0,
                    hoverOffset: 0
                }]
            },
            options: {
                rotation: -90,       // start at 9 o'clock
                circumference: 180,  // draw only the top semicircle
                cutout: '74%',
                responsive: true,
                maintainAspectRatio: true,
                aspectRatio: 2,
                animation: { duration: 500, easing: 'easeOutQuart' },
                layout: { padding: 0 },
                plugins: {
                    legend:  { display: false },
                    tooltip: { enabled: false }
                }
            },
            plugins: [this._buildTextPlugin(scoreText, gradeLetter, fillColor, gradeColor)]
        };

        if (this._chart) {
            this._chart.destroy();
            this._chart = null;
        }

        // eslint-disable-next-line no-undef
        this._chart = new Chart(canvas, config);

        this._lastGrade  = this.grade;  // must mirror the order below
        this._lastScore  = this.score;
        this._lastStatus = this.status;
        this._lastGrade  = this.grade;
    }

    // Returns a Chart.js plugin that draws the score number and grade letter
    // inside the cutout hole. scoreTxt is a string ("65", "--", "…");
    // gradeLetter is a single letter ("C") or empty string.
    _buildTextPlugin(scoreTxt, gradeLetter, fillColor, gradeColor) {
        return {
            id: 'gaugeCenter',
            afterDraw(chart) {
                const { ctx, chartArea } = chart;
                if (!chartArea) return;

                // Mathematical centre of the doughnut circle (bottom midpoint of the arc)
                const cx = (chartArea.left + chartArea.right)  / 2;
                const cy = (chartArea.top  + chartArea.bottom) / 2;

                ctx.save();
                ctx.textAlign = 'center';

                if (gradeLetter) {
                    // Score number — sits above centre, leaving room for grade below
                    ctx.font = 'bold 34px "Salesforce Sans", Arial, sans-serif';
                    ctx.fillStyle = '#181818';
                    ctx.textBaseline = 'alphabetic';
                    ctx.fillText(scoreTxt, cx, cy - 2);

                    // Grade letter — sits just below centre in matching colour
                    ctx.font = 'bold 16px "Salesforce Sans", Arial, sans-serif';
                    ctx.fillStyle = gradeColor;
                    ctx.textBaseline = 'top';
                    ctx.fillText(gradeLetter, cx, cy + 3);
                } else {
                    // No grade yet — centre the score vertically in the space
                    ctx.font = 'bold 36px "Salesforce Sans", Arial, sans-serif';
                    ctx.fillStyle = '#181818';
                    ctx.textBaseline = 'middle';
                    ctx.fillText(scoreTxt, cx, cy - 4);
                }

                ctx.restore();
            }
        };
    }
}
