import SwiftUI
import Combine

struct SmartDataInputForm: View {
    @State private var dataType: OPCDataType = .double
    @State private var value: String = ""
    @State private var arrayValues: [String] = [""]
    @State private var structureFields: [StructureField] = []
    @State private var validationError: String?
    @State private var showPreview = false
    @StateObject private var validator = DataValidator()
    
    let nodeInfo: NodeInfo
    let onSubmit: (Any, OPCDataType) -> Void

    init(nodeInfo: NodeInfo, initialDataType: OPCDataType? = nil, onSubmit: @escaping (Any, OPCDataType) -> Void) {
        self.nodeInfo = nodeInfo
        self.onSubmit = onSubmit
        if let initialDataType {
            _dataType = State(initialValue: initialDataType)
        }
    }
    
    enum OPCDataType: String, CaseIterable {
        case boolean = "Boolean"
        case byte = "Byte"
        case int16 = "Int16"
        case int32 = "Int32"
        case int64 = "Int64"
        case float = "Float"
        case double = "Double"
        case string = "String"
        case dateTime = "DateTime"
        case byteString = "ByteString"
        case array = "Array"
        case structure = "Structure"
        
        var icon: String {
            switch self {
            case .boolean: return "switch.2"
            case .byte, .int16, .int32, .int64: return "number"
            case .float, .double: return "number.circle"
            case .string: return "textformat"
            case .dateTime: return "calendar"
            case .byteString: return "doc.badge.gearshape"
            case .array: return "square.stack.3d.up"
            case .structure: return "square.grid.3x1.below.line.grid.1x2"
            }
        }
    }
    
    struct StructureField: Identifiable {
        let id = UUID()
        var name: String
        var type: OPCDataType
        var value: String
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            ScrollView {
                VStack(spacing: OPCTheme.Spacing.lg) {
                    dataTypeSelector
                    
                    Divider()
                    
                    inputSection
                    
                    if let error = validationError {
                        errorView(error)
                    }
                    
                    if showPreview {
                        previewSection
                    }
                }
                .padding()
            }
            
            bottomActionBar
        }
        .background(OPCTheme.Colors.background)
        .onChange(of: value) { _, newValue in
            validateInput(newValue)
        }
    }
    
    var headerView: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.sm) {
            HStack {
                Image(systemName: nodeInfo.nodeClass.systemImage)
                    .font(.system(size: 20))
                    .foregroundColor(nodeInfo.nodeClass.color)
                
                VStack(alignment: .leading) {
                    Text("Write to Node")
                        .font(OPCTheme.Typography.headline)
                    Text(nodeInfo.displayName)
                        .font(OPCTheme.Typography.caption1)
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                }
                
                Spacer()
                
                if let currentValue = nodeInfo.value {
                    VStack(alignment: .trailing) {
                        Text("Current")
                            .font(OPCTheme.Typography.caption2)
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                        Text(currentValue)
                            .font(OPCTheme.Typography.callout)
                            .fontWeight(.medium)
                            .foregroundColor(OPCTheme.Colors.success)
                    }
                }
            }
            .padding()
        }
        .background(OPCTheme.Colors.secondaryBackground)
    }
    
    var dataTypeSelector: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.sm) {
            Text("Data Type")
                .font(OPCTheme.Typography.subheadline)
                .foregroundColor(OPCTheme.Colors.secondaryText)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPCTheme.Spacing.sm) {
                    ForEach(OPCDataType.allCases, id: \.self) { type in
                        DataTypeChip(
                            type: type,
                            isSelected: dataType == type,
                            action: {
                                withAnimation(OPCTheme.Animation.fast) {
                                    dataType = type
                                    resetInput()
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var inputSection: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.md) {
            Text("Value")
                .font(OPCTheme.Typography.subheadline)
                .foregroundColor(OPCTheme.Colors.secondaryText)
            
            switch dataType {
            case .boolean:
                BooleanInput(value: Binding(
                    get: { value == "true" },
                    set: { value = $0 ? "true" : "false" }
                ))
                
            case .byte, .int16, .int32, .int64:
                NumericInput(
                    value: $value,
                    type: dataType,
                    validator: validator
                )
                
            case .float, .double:
                FloatingPointInput(
                    value: $value,
                    type: dataType,
                    validator: validator
                )
                
            case .string:
                StringInput(value: $value)
                
            case .dateTime:
                DateTimeInput(value: $value)
                
            case .byteString:
                ByteStringInput(value: $value)
                
            case .array:
                ArrayInput(values: $arrayValues, elementType: .double)
                
            case .structure:
                StructureInput(fields: $structureFields)
            }
            
            if validator.hasValidationRules(for: dataType) {
                ValidationHints(dataType: dataType)
            }
        }
    }
    
    var previewSection: some View {
        VStack(alignment: .leading, spacing: OPCTheme.Spacing.sm) {
            HStack {
                Text("Preview")
                    .font(OPCTheme.Typography.headline)
                
                Spacer()
                
                Button(action: { showPreview = false }) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 14))
                }
            }
            
            CodePreview(
                dataType: dataType,
                value: value,
                arrayValues: arrayValues,
                structureFields: structureFields
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(OPCTheme.Colors.tertiaryBackground)
        )
    }
    
    var bottomActionBar: some View {
        HStack(spacing: OPCTheme.Spacing.md) {
            Button(action: { showPreview.toggle() }) {
                Label(showPreview ? "Hide Preview" : "Show Preview", 
                      systemImage: showPreview ? "eye.slash" : "eye")
                    .font(OPCTheme.Typography.callout)
            }
            
            Spacer()
            
            Button("Clear") {
                resetInput()
            }
            .foregroundColor(OPCTheme.Colors.error)
            
            Button("Write") {
                submitValue()
            }
            .buttonStyle(.borderedProminent)
            .disabled(validationError != nil || value.isEmpty)
        }
        .padding()
        .background(OPCTheme.Colors.secondaryBackground)
    }
    
    func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(OPCTheme.Colors.error)
            
            Text(error)
                .font(OPCTheme.Typography.caption1)
                .foregroundColor(OPCTheme.Colors.error)
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.sm)
                .fill(OPCTheme.Colors.error.opacity(0.1))
        )
    }
    
    func validateInput(_ input: String) {
        validationError = validator.validate(input, for: dataType)
    }
    
    func resetInput() {
        value = ""
        arrayValues = [""]
        structureFields = []
        validationError = nil
    }
    
    func submitValue() {
        let parsedValue = parseValue()
        onSubmit(parsedValue, dataType)
    }
    
    func parseValue() -> Any {
        switch dataType {
        case .boolean:
            return value == "true"
        case .byte:
            return UInt8(value) ?? 0
        case .int16:
            return Int16(value) ?? 0
        case .int32:
            return Int32(value) ?? 0
        case .int64:
            return Int64(value) ?? 0
        case .float:
            return Float(value) ?? 0.0
        case .double:
            return Double(value) ?? 0.0
        case .string:
            return value
        case .dateTime:
            return ISO8601DateFormatter().date(from: value) ?? Date()
        case .byteString:
            return Data(value.utf8)
        case .array:
            return arrayValues
        case .structure:
            return structureFields.reduce(into: [String: String]()) { result, field in
                result[field.name] = field.value
            }
        }
    }
}

struct DataTypeChip: View {
    let type: SmartDataInputForm.OPCDataType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: OPCTheme.Spacing.xs) {
                Image(systemName: type.icon)
                    .font(.system(size: 14))
                
                Text(type.rawValue)
                    .font(OPCTheme.Typography.caption1)
            }
            .foregroundColor(isSelected ? .white : OPCTheme.Colors.primary)
            .padding(.horizontal, OPCTheme.Spacing.md)
            .padding(.vertical, OPCTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: OPCTheme.Radius.sm)
                    .fill(isSelected ? OPCTheme.Colors.primary : OPCTheme.Colors.primary.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct BooleanInput: View {
    @Binding var value: Bool
    
    var body: some View {
        HStack {
            Text("Value:")
                .font(OPCTheme.Typography.callout)
                .foregroundColor(OPCTheme.Colors.secondaryText)
            
            Spacer()
            
            Toggle("", isOn: $value)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: OPCTheme.Colors.primary))
            
            Text(value ? "TRUE" : "FALSE")
                .font(OPCTheme.Typography.callout)
                .fontWeight(.medium)
                .foregroundColor(value ? OPCTheme.Colors.success : OPCTheme.Colors.secondaryText)
                .frame(width: 60)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(OPCTheme.Colors.secondaryBackground)
        )
    }
}

struct NumericInput: View {
    @Binding var value: String
    let type: SmartDataInputForm.OPCDataType
    let validator: DataValidator
    @State private var sliderValue: Double = 0
    
    var range: ClosedRange<Double> {
        switch type {
        case .byte: return 0...255
        case .int16: return Double(Int16.min)...Double(Int16.max)
        case .int32: return Double(Int32.min)...Double(Int32.max)
        case .int64: return Double(Int64.min)...Double(Int64.max)
        default: return 0...100
        }
    }
    
    var body: some View {
        VStack(spacing: OPCTheme.Spacing.md) {
            HStack {
                TextField("Enter value", text: $value)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                
                Stepper("", value: Binding(
                    get: { Double(value) ?? 0 },
                    set: { value = String(Int($0)) }
                ), in: range)
            }
            
            if type == .byte || type == .int16 {
                VStack(spacing: OPCTheme.Spacing.sm) {
                    Slider(value: Binding(
                        get: { Double(value) ?? 0 },
                        set: { 
                            value = String(Int($0))
                            sliderValue = $0
                        }
                    ), in: range)
                    .accentColor(OPCTheme.Colors.primary)
                    
                    HStack {
                        Text(String(Int(range.lowerBound)))
                            .font(OPCTheme.Typography.caption2)
                            .foregroundColor(OPCTheme.Colors.tertiaryText)
                        
                        Spacer()
                        
                        Text(String(Int(range.upperBound)))
                            .font(OPCTheme.Typography.caption2)
                            .foregroundColor(OPCTheme.Colors.tertiaryText)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(OPCTheme.Colors.secondaryBackground)
        )
    }
}

struct FloatingPointInput: View {
    @Binding var value: String
    let type: SmartDataInputForm.OPCDataType
    let validator: DataValidator
    @State private var precision = 2
    
    var body: some View {
        VStack(spacing: OPCTheme.Spacing.md) {
            HStack {
                TextField("Enter value", text: $value)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                
                VStack {
                    Text("Precision")
                        .font(OPCTheme.Typography.caption2)
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                    
                    Stepper("\(precision)", value: $precision, in: 0...10)
                        .labelsHidden()
                }
            }
            
            if let doubleValue = Double(value) {
                Text("Formatted: \(doubleValue, specifier: "%.\(precision)f")")
                    .font(OPCTheme.Typography.caption1)
                    .foregroundColor(OPCTheme.Colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(OPCTheme.Colors.secondaryBackground)
        )
    }
}

struct StringInput: View {
    @Binding var value: String
    @State private var characterCount = 0
    
    var body: some View {
        VStack(spacing: OPCTheme.Spacing.sm) {
            TextEditor(text: $value)
                .font(OPCTheme.Typography.body)
                .frame(minHeight: 100)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: OPCTheme.Radius.sm)
                        .stroke(OPCTheme.Colors.border, lineWidth: 1)
                )
                .onChange(of: value) { _, newValue in
                    characterCount = newValue.count
                }
            
            HStack {
                Text("\(characterCount) characters")
                    .font(OPCTheme.Typography.caption2)
                    .foregroundColor(OPCTheme.Colors.tertiaryText)
                
                Spacer()
                
                Menu {
                    Button("Clear") { value = "" }
                    Button("Uppercase") { value = value.uppercased() }
                    Button("Lowercase") { value = value.lowercased() }
                    Button("Capitalize") { value = value.capitalized }
                } label: {
                    Image(systemName: "text.quote")
                        .font(.system(size: 14))
                        .foregroundColor(OPCTheme.Colors.primary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(OPCTheme.Colors.secondaryBackground)
        )
    }
}

struct DateTimeInput: View {
    @Binding var value: String
    @State private var selectedDate = Date()
    @State private var includeTime = true
    
    var body: some View {
        VStack(spacing: OPCTheme.Spacing.md) {
            DatePicker(
                "Select Date",
                selection: $selectedDate,
                displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date]
            )
            .datePickerStyle(.compact)
            .onChange(of: selectedDate) { _, newDate in
                value = ISO8601DateFormatter().string(from: newDate)
            }
            
            Toggle("Include Time", isOn: $includeTime)
                .font(OPCTheme.Typography.callout)
            
            if !value.isEmpty {
                HStack {
                    Text("ISO 8601:")
                        .font(OPCTheme.Typography.caption2)
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                    
                    Text(value)
                        .font(OPCTheme.Typography.monospacedSmall)
                        .foregroundColor(OPCTheme.Colors.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                        #endif
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(OPCTheme.Colors.secondaryBackground)
        )
    }
}

struct ByteStringInput: View {
    @Binding var value: String
    @State private var inputMode = InputMode.hex
    
    enum InputMode: String, CaseIterable {
        case hex = "Hexadecimal"
        case base64 = "Base64"
        case utf8 = "UTF-8"
    }
    
    var body: some View {
        VStack(spacing: OPCTheme.Spacing.md) {
            Picker("Input Mode", selection: $inputMode) {
                ForEach(InputMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            TextEditor(text: $value)
                .font(OPCTheme.Typography.monospacedSmall)
                .frame(minHeight: 100)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: OPCTheme.Radius.sm)
                        .stroke(OPCTheme.Colors.border, lineWidth: 1)
                )
            
            if inputMode == .hex {
                Text("Enter hex values (e.g., 48 65 6C 6C 6F)")
                    .font(OPCTheme.Typography.caption2)
                    .foregroundColor(OPCTheme.Colors.tertiaryText)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(OPCTheme.Colors.secondaryBackground)
        )
    }
}

struct ArrayInput: View {
    @Binding var values: [String]
    let elementType: SmartDataInputForm.OPCDataType
    
    var body: some View {
        VStack(spacing: OPCTheme.Spacing.md) {
            HStack {
                Text("Array Elements (\(values.count))")
                    .font(OPCTheme.Typography.subheadline)
                
                Spacer()
                
                Button(action: { values.append("") }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(OPCTheme.Colors.primary)
                }
            }
            
            ForEach(values.indices, id: \.self) { index in
                HStack {
                    Text("[\(index)]")
                        .font(OPCTheme.Typography.monospacedSmall)
                        .foregroundColor(OPCTheme.Colors.secondaryText)
                        .frame(width: 40)
                    
                    TextField("Value", text: $values[index])
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: { values.remove(at: index) }) {
                        Image(systemName: "minus.circle")
                            .foregroundColor(OPCTheme.Colors.error)
                    }
                    .disabled(values.count <= 1)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(OPCTheme.Colors.secondaryBackground)
        )
    }
}

struct StructureInput: View {
    @Binding var fields: [SmartDataInputForm.StructureField]
    
    var body: some View {
        VStack(spacing: OPCTheme.Spacing.md) {
            HStack {
                Text("Structure Fields")
                    .font(OPCTheme.Typography.subheadline)
                
                Spacer()
                
                Button(action: addField) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(OPCTheme.Colors.primary)
                }
            }
            
            ForEach(fields.indices, id: \.self) { index in
                VStack(spacing: OPCTheme.Spacing.sm) {
                    HStack {
                        TextField("Field Name", text: $fields[index].name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: 150)
                        
                        Picker("", selection: $fields[index].type) {
                            ForEach([SmartDataInputForm.OPCDataType.string, .double, .int32, .boolean], id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .frame(maxWidth: 120)
                        
                        TextField("Value", text: $fields[index].value)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button(action: { fields.remove(at: index) }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(OPCTheme.Colors.error)
                        }
                    }
                }
            }
            
            if fields.isEmpty {
                Text("No fields added")
                    .font(OPCTheme.Typography.caption1)
                    .foregroundColor(OPCTheme.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.md)
                .fill(OPCTheme.Colors.secondaryBackground)
        )
    }
    
    func addField() {
        fields.append(SmartDataInputForm.StructureField(
            name: "field\(fields.count + 1)",
            type: .string,
            value: ""
        ))
    }
}

struct ValidationHints: View {
    let dataType: SmartDataInputForm.OPCDataType
    
    var hints: [String] {
        switch dataType {
        case .byte:
            return ["Range: 0 to 255", "Unsigned 8-bit integer"]
        case .int16:
            return ["Range: -32,768 to 32,767", "Signed 16-bit integer"]
        case .int32:
            return ["Range: -2,147,483,648 to 2,147,483,647", "Signed 32-bit integer"]
        case .float:
            return ["32-bit floating point", "~7 digits precision"]
        case .double:
            return ["64-bit floating point", "~15 digits precision"]
        case .dateTime:
            return ["ISO 8601 format", "Example: 2024-01-15T10:30:00Z"]
        default:
            return []
        }
    }
    
    var body: some View {
        if !hints.isEmpty {
            VStack(alignment: .leading, spacing: OPCTheme.Spacing.xs) {
                ForEach(hints, id: \.self) { hint in
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(OPCTheme.Colors.info)
                        
                        Text(hint)
                            .font(OPCTheme.Typography.caption2)
                            .foregroundColor(OPCTheme.Colors.secondaryText)
                    }
                }
            }
            .padding(OPCTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: OPCTheme.Radius.sm)
                    .fill(OPCTheme.Colors.info.opacity(0.1))
            )
        }
    }
}

struct CodePreview: View {
    let dataType: SmartDataInputForm.OPCDataType
    let value: String
    let arrayValues: [String]
    let structureFields: [SmartDataInputForm.StructureField]
    
    var formattedCode: String {
        switch dataType {
        case .array:
            return "[\n" + arrayValues.enumerated().map { "  [\($0)]: \($1)" }.joined(separator: ",\n") + "\n]"
        case .structure:
            let fields = structureFields.map { "  \"\($0.name)\": \($0.value)" }.joined(separator: ",\n")
            return "{\n\(fields)\n}"
        default:
            return "\(dataType.rawValue): \(value)"
        }
    }
    
    var body: some View {
        ScrollView {
            Text(formattedCode)
                .font(OPCTheme.Typography.monospacedSmall)
                .foregroundColor(OPCTheme.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPCTheme.Radius.sm)
                .fill(Color.black.opacity(0.05))
        )
    }
}

class DataValidator: ObservableObject {
    @Published var validationErrors: [String: String] = [:]
    
    func validate(_ input: String, for type: SmartDataInputForm.OPCDataType) -> String? {
        switch type {
        case .byte:
            guard let value = UInt8(input), value >= 0 && value <= 255 else {
                return "Value must be between 0 and 255"
            }
        case .int16:
            guard let _ = Int16(input) else {
                return "Invalid Int16 value"
            }
        case .int32:
            guard let _ = Int32(input) else {
                return "Invalid Int32 value"
            }
        case .int64:
            guard let _ = Int64(input) else {
                return "Invalid Int64 value"
            }
        case .float:
            guard let _ = Float(input) else {
                return "Invalid float value"
            }
        case .double:
            guard let _ = Double(input) else {
                return "Invalid double value"
            }
        case .dateTime:
            guard ISO8601DateFormatter().date(from: input) != nil else {
                return "Invalid date format. Use ISO 8601"
            }
        default:
            break
        }
        return nil
    }
    
    func hasValidationRules(for type: SmartDataInputForm.OPCDataType) -> Bool {
        switch type {
        case .byte, .int16, .int32, .int64, .float, .double, .dateTime:
            return true
        default:
            return false
        }
    }
}
