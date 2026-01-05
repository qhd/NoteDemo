//
//  ViewController.swift
//  NoteDemo
//
//  Created by 邱浩东 on 2026/1/5.
//

import UIKit

class ViewController: UIViewController {
    private let canvasView = CanvasView()
    private let modeSegment = UISegmentedControl(items: ["画线", "选择"])

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        modeSegment.selectedSegmentIndex = 0
        modeSegment.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        navigationItem.titleView = modeSegment
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "清除", style: .plain, target: self, action: #selector(clearCanvas))
        view.addSubview(canvasView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        canvasView.frame = view.bounds
    }

    @objc private func modeChanged() {
        canvasView.isSelectionMode = modeSegment.selectedSegmentIndex == 1
    }

    @objc private func clearCanvas() {
        canvasView.clear()
    }
}

class CanvasView: UIView {
    private var line: [CGPoint] = []                             // 线条的点
    private var currentTransform: CGAffineTransform = .identity  // 当前变换矩阵（平移或旋转）
    private var transformCenter: CGPoint = .zero                 // 变换中心点（旋转围绕此点）
    private var startPoint: CGPoint?                             // 触摸起始点
    private var isRotating = false                               // 是否正在旋转
    private var isSelected = false                               // 线条是否被选中

    var isSelectionMode = false {
        didSet { isSelected = false; currentTransform = .identity; setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 清除线条
    func clear() {
        line.removeAll()
        isSelected = false
        setNeedsDisplay()
    }

    /// 绘制视图内容
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), line.count > 1 else { return }
        ctx.setStrokeColor(UIColor.black.cgColor)
        ctx.setLineWidth(2)

        // 绘制线条（选中时应用变换）
        if isSelected && currentTransform != .identity {
            ctx.saveGState()
            ctx.translateBy(x: transformCenter.x, y: transformCenter.y)
            ctx.concatenate(currentTransform)
            ctx.translateBy(x: -transformCenter.x, y: -transformCenter.y)
            drawLine(in: ctx)
            ctx.restoreGState()
        } else {
            drawLine(in: ctx)
        }

        // 绘制选择框
        if isSelected {
            drawSelectionBox(in: ctx)
        }
    }

    /// 绘制线条
    private func drawLine(in ctx: CGContext) {
        ctx.beginPath()
        ctx.move(to: line[0])
        for i in 1..<line.count { ctx.addLine(to: line[i]) }
        ctx.strokePath()
    }

    /// 绘制选择框和旋转手柄
    private func drawSelectionBox(in ctx: CGContext) {
        let box = boundingBox()
        let corners = [
            CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
            CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)
        ].map { applyTransform($0) }

        // 蓝色边框
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.beginPath()
        ctx.move(to: corners[0])
        corners.dropFirst().forEach { ctx.addLine(to: $0) }
        ctx.closePath()
        ctx.strokePath()

        // 旋转手柄
        let pos = rotateHandlePos()
        ctx.setFillColor(UIColor.systemBlue.cgColor)
        ctx.fillEllipse(in: CGRect(x: pos.x - 12, y: pos.y - 12, width: 24, height: 24))
    }

    /// 触摸开始
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }

        if isSelectionMode {
            if isSelected {
                // 计算变换中心点
                transformCenter = CGPoint(x: boundingBox().midX, y: boundingBox().midY)
                // 点击旋转手柄
                if dist(point, rotateHandlePos()) < 20 {
                    isRotating = true; startPoint = point; return
                }
                // 点击选中区域（平移）
                if boundingBox().contains(point) {
                    startPoint = point; return
                }
            }
            // 点击线条选中
            isSelected = line.contains(where: { dist(point, $0) < 15 })
            if isSelected {
                transformCenter = CGPoint(x: boundingBox().midX, y: boundingBox().midY)
            }
            setNeedsDisplay()
        } else {
            line = [point]
        }
    }

    /// 触摸移动
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }

        if isSelectionMode {
            guard let start = startPoint, isSelected else { return }
            if isRotating {
                // 计算旋转角度：当前触点相对中心的角度 - 起始触点相对中心的角度
                let a1 = atan2(start.y - transformCenter.y, start.x - transformCenter.x)
                let a2 = atan2(point.y - transformCenter.y, point.x - transformCenter.x)
                currentTransform = CGAffineTransform(rotationAngle: a2 - a1)
            } else {
                // 计算平移距离：当前触点 - 起始触点
                currentTransform = CGAffineTransform(translationX: point.x - start.x, y: point.y - start.y)
            }
            setNeedsDisplay()
        } else {
            line.append(point)
            setNeedsDisplay()
        }
    }

    /// 触摸结束
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isSelectionMode {
            // 应用变换到点坐标
            if isSelected && currentTransform != .identity {
                line = line.map { applyTransform($0) }
                currentTransform = .identity
            }
            startPoint = nil; isRotating = false
            setNeedsDisplay()
        }
    }

    /// 计算边界框
    private func boundingBox() -> CGRect {
        let xs = line.map { $0.x }, ys = line.map { $0.y }
        return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0,
                      width: (xs.max() ?? 0) - (xs.min() ?? 0),
                      height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }

    /// 将变换应用到点（围绕中心点）
    private func applyTransform(_ p: CGPoint) -> CGPoint {
        let t = CGPoint(x: p.x - transformCenter.x, y: p.y - transformCenter.y)
        let r = t.applying(currentTransform)
        return CGPoint(x: r.x + transformCenter.x, y: r.y + transformCenter.y)
    }

    /// 计算旋转手柄位置
    private func rotateHandlePos() -> CGPoint {
        let box = boundingBox()
        let c1 = applyTransform(CGPoint(x: box.maxX, y: box.minY))
        let c2 = applyTransform(CGPoint(x: box.maxX, y: box.maxY))
        let mid = CGPoint(x: (c1.x + c2.x) / 2, y: (c1.y + c2.y) / 2)
        let dx = c2.x - c1.x, dy = c2.y - c1.y
        let len = sqrt(dx * dx + dy * dy)
        return len > 0 ? CGPoint(x: mid.x + dy / len * 30, y: mid.y - dx / len * 30) : mid
    }

    /// 计算两点距离
    private func dist(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2))
    }
}

