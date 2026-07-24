//
//  QsoTableModel.swift
//  Backing store for the QSO log NSTableView.
//

import AppKit

public final class QsoTableModel: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    public var rows: [[String]] = []
    /// Called when the selected row changes; receives the selected row index
    /// or nil when the selection is cleared. Used to update the callsign-info
    /// bar with the selected QSO's details.
    public var onSelectionChange: ((Int?) -> Void)?

    public func appendRow(_ row: [String]) {
        rows.append(row)
    }

    public func updateLastError(_ err: String) {
        guard !rows.isEmpty else { return }
        if rows[rows.count - 1].count > 5 {
            rows[rows.count - 1][5] = err
        }
    }

    /// Update the Chk cell (column 5) of a specific row by index.
    public func updateRowError(_ row: Int, _ err: String) {
        guard row >= 0, row < rows.count, rows[row].count > 5 else { return }
        rows[row][5] = err
    }

    public func clear() { rows.removeAll() }

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let col = tableColumn,
              let idx = tableView.tableColumns.firstIndex(of: col),
              row < rows.count, idx < rows[row].count else { return nil }
        return rows[row][idx]
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn,
              let idx = tableView.tableColumns.firstIndex(of: col),
              row < rows.count, idx < rows[row].count else { return nil }
        // Reuse cells the standard way; set .textField so it doesn't accumulate
        // duplicate subviews across reloads.
        let cell = tableView.makeView(withIdentifier: col.identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = col.identifier
        if cell.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            tf.isSelectable = true
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let tf = cell.textField!
        tf.stringValue = rows[row][idx]
        // Highlight the Chk (error) column in red, all others in the label colour.
        tf.textColor = (idx == 5) ? .systemRed : .labelColor
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView else { return }
        let idx = tv.selectedRow
        // -1 means no selection (cleared) — signal nil so the caller can fall
        // back to showing the most-recent QSO's info.
        onSelectionChange?(idx >= 0 ? idx : nil)
    }
}
