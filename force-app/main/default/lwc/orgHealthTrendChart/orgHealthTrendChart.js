/**
 * Score trend chart using Chart.js.
 * Displays composite health scores over the last N scans with grade threshold lines.
 * Colors each data point by grade (green/yellow/red).
 */

import { LightningElement, api, track } from 'lwc';
import { loadScript }                   from 'lightning/platformResourceLoader';
import chartjs                          from '@salesforce/resourceUrl/chartjs';

/**
 * Maps a score to a colour by grade: A (green), B–C (orange), D+ (red).
 * @param {number} score - Composite health score (0–100)
 * @returns {string} Hex colour code
 */
function gradeColor(score) {
    if (score >= 75) return '#2e844a';
    if (score >= 60) return '#dd7a01';
    return '#ea001e';
}

/**
 * Formats an ISO timestamp to a short date string (e.g., "15 Jun").
 * @param {string} iso - ISO 8601 datetime string
 * @returns {string} Formatted date (e.g., "15 Jun")
 */
function shortDate(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

export default class OrgHealthTrendChart extends LightningElement {
    /** @type {Array<HealthScan__c>} Array of completed scans (oldest to newest). */
    @api trend = [];

    @track _libLoaded = false;
    _chart;

    /**
     * Checks if there is enough trend data to render the chart.
     * @returns {boolean} True if trend has at least 2 scans
     */
    get hasTrend() {
        return (this.trend || []).length >= 2;
    }

    /**
     * Lifecycle hook: load Chart.js library and render chart once available.
     */
    connectedCallback() {
        if (!this._libLoaded) {
            loadScript(this, chartjs)
                .then(() => {
                    this._libLoaded = true;
                    this._renderChart();
                })
                .catch(err => console.error('Chart.js load error:', err));
        }
    }

    /**
     * Lifecycle hook: re-render the chart whenever new trend data arrives from the parent.
     */
    renderedCallback() {
        if (this._libLoaded && this.hasTrend) {
            this._renderChart();
        }
    }

    /**
     * Lifecycle hook: destroy the Chart.js instance to avoid memory leaks.
     */
    disconnectedCallback() {
        if (this._chart) {
            this._chart.destroy();
            this._chart = null;
        }
    }

    /**
     * Renders or updates the trend chart using Chart.js.
     * Displays scores over time with dashed grade threshold lines (A/B/C/D).
     * Data points are coloured by grade.
     * @private
     */
    _renderChart() {
        if (!this._libLoaded || !this.hasTrend) return;

        const canvas = this.template.querySelector('canvas.trend-canvas');
        if (!canvas) return;

        // Oldest → newest left to right
        const scans = [...(this.trend || [])].reverse();

        const labels = scans.map(s => shortDate(s.ScanStartTime__c));
        const scores = scans.map(s => +(s.CompositeScore__c || 0).toFixed(1));
        const pointColors = scores.map(gradeColor);

        // Grade threshold annotation lines
        const gradeLines = [
            { score: 90, color: '#2e844a', label: 'A' },
            { score: 75, color: '#3ba755', label: 'B' },
            { score: 60, color: '#dd7a01', label: 'C' },
            { score: 40, color: '#ea001e', label: 'D' }
        ];

        const config = {
            type: 'line',
            data: {
                labels,
                datasets: [
                    {
                        label: 'Health Score',
                        data: scores,
                        borderColor: '#0176d3',
                        backgroundColor: 'rgba(1, 118, 211, 0.08)',
                        pointBackgroundColor: pointColors,
                        pointBorderColor: '#ffffff',
                        pointBorderWidth: 2,
                        pointRadius: 5,
                        pointHoverRadius: 7,
                        borderWidth: 2.5,
                        tension: 0.3,
                        fill: false
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                aspectRatio: 1.75,
                interaction: { mode: 'index', intersect: false },
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        callbacks: {
                            label: ctx => `Score: ${ctx.parsed.y}`
                        }
                    },
                    // Inline annotation via beforeDraw
                    customGradeLines: true
                },
                layout: {
                    // Right padding reserves canvas space for the A/B/C/D labels
                    // drawn just outside chartArea.right by the grade-lines plugin
                    padding: { right: 24 }
                },
                scales: {
                    y: {
                        min: 0,
                        max: 100,
                        ticks: {
                            stepSize: 20,
                            color: '#706e6b',
                            font: { size: 11 }
                        },
                        grid: { color: 'rgba(0,0,0,0.06)' }
                    },
                    x: {
                        ticks: {
                            color: '#706e6b',
                            font: { size: 11 },
                            maxRotation: 35,
                            minRotation: 0
                        },
                        grid: { display: false }
                    }
                }
            },
            plugins: [this._gradeLinesPlugin(gradeLines)]
        };

        if (this._chart) {
            this._chart.destroy();
            this._chart = null;
        }

        // Chart.js attaches to globalThis.Chart after the UMD script loads
        // eslint-disable-next-line no-undef
        this._chart = new Chart(canvas, config);
    }

    /**
     * Custom Chart.js plugin that draws dashed horizontal lines at each grade threshold
     * (A/B/C/D) and labels them to the right of the chart area.
     * @private
     * @param {Array<{score: number, color: string, label: string}>} gradeLines - Grade thresholds
     * @returns {Object} Chart.js plugin object
     */
    _gradeLinesPlugin(gradeLines) {
        return {
            id: 'gradeLinesPlugin',
            beforeDraw(chart) {
                const { ctx, chartArea, scales } = chart;
                if (!chartArea) return;
                ctx.save();
                gradeLines.forEach(gl => {
                    const y = scales.y.getPixelForValue(gl.score);
                    ctx.beginPath();
                    ctx.setLineDash([4, 3]);
                    ctx.strokeStyle = gl.color;
                    ctx.globalAlpha = 0.55;
                    ctx.lineWidth = 1;
                    ctx.moveTo(chartArea.left, y);
                    ctx.lineTo(chartArea.right, y);
                    ctx.stroke();
                    ctx.setLineDash([]);
                    ctx.globalAlpha = 1;
                    ctx.fillStyle = gl.color;
                    ctx.font = 'bold 10px Arial';
                    ctx.textAlign = 'left';
                    ctx.fillText(gl.label, chartArea.right + 5, y + 3);
                });
                ctx.restore();
            }
        };
    }
}
