//
//  OneWheelGraphView.swift
//  OneWheel
//
//  Created by David Brodsky on 1/5/18.
//  Copyright © 2018 David Brodsky. All rights reserved.
//

import UIKit

class OneWheelGraphView: UIView {
    
    private let rideData = RideLocalData()
    
    let zoomHintColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0).cgColor
    
    var dataSource: GraphDataSource?
    var dataRange = CGPoint(x: 0.0, y: 1.0) //x - min, y - max
    var series = [String: Series]()
    var bgColor: UIColor = UIColor(white: 0.0, alpha: 1.0) {
        didSet {
            self.backgroundColor = bgColor
        }
    }
    var bgTransparentColor: CGColor {
        get {
            return bgColor.cgColor.copy(alpha: 0.0)!
        }
    }
    
    var portraitMode: Bool = false {
        didSet {
            NSLog("Set portrait mode \(portraitMode)")
            if portraitMode {
                resetDataRange()
            }
        }
    }
    
    // Parallel cache arrays of state and x placement
    var stateCacheDataCount: Int = 0
    var stateCache = [OneWheelState]()
    var stateXPosCache = [CGFloat]()
    
    // Display rects
    var seriesRect = CGRect()
    var seriesAxisRect = CGRect()
    var timeLabelsRect = CGRect()
    
    // Layers managed by view
    var zoomLayer = CALayer()
    var axisLabelLayer = CALayer()
    var timeAxisLabels : [CATextLayer]? = nil  // sublayers of axisLabelLayer
    
    // Gestures
    var lastScale: CGFloat = 1.0
    var lastScalePoint: CGPoint? = nil
    var isGesturing = false
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        calculateRects()
        
        zoomLayer.frame = seriesAxisRect
        zoomLayer.masksToBounds = true
        self.layer.addSublayer(zoomLayer)
        
        axisLabelLayer.frame = seriesAxisRect
        self.layer.addSublayer(axisLabelLayer)
    }
    
    private func calculateRects() {
        NSLog("Calculate rects with bounds \(self.bounds)")
        let seriesAxisRect = self.bounds.insetBy(dx: 0.0, dy: 11.0).applying(CGAffineTransform(translationX: 0.0, y: -11.0))
        let timeLabelsRect = portraitMode ? self.bounds.insetBy(dx: 20.0, dy: 0.0) : self.bounds.insetBy(dx: 40.0, dy: 0.0).applying(CGAffineTransform(translationX: 7.0, y: 0.0)) // last affineT is a janky compensation for the MPH / Battery label width differences :/
        let seriesRect = portraitMode ? seriesAxisRect.insetBy(dx: 20.0, dy: 0.0).applying(CGAffineTransform(translationX: -20.0, y: 0.0)) : seriesAxisRect.insetBy(dx: 45.0, dy: 0.0).applying(CGAffineTransform(translationX: 7.0, y: 0.0))
    
        self.seriesRect = seriesRect
        self.seriesAxisRect = seriesAxisRect
        self.timeLabelsRect = timeLabelsRect
    }
    
    public override func layoutSublayers(of layer: CALayer) {

        if (!isGesturing) {
            NSLog("CALayer - layoutSublayers with bounds \(self.bounds) frame \(self.frame)")
            refreshGraph()
        }
        super.layoutSublayers(of: layer)
    }
    
    private func resizeLayers() {
        calculateRects()
        
        // Resize layers, but do not reset transform
        self.zoomLayer.bounds = seriesRect
        self.zoomLayer.position = CGPoint(x: seriesRect.midX, y: seriesRect.midY)
        
        self.axisLabelLayer.bounds = seriesAxisRect
        self.axisLabelLayer.position = CGPoint(x: seriesAxisRect.midX, y: seriesAxisRect.midY)
        
        for (_, series) in self.series {
            series.resizeLayers(frame: seriesRect, graphView: self)
        }
    }
    
    func onPinch(_ sender: UIPinchGestureRecognizer) {
        if portraitMode {
            return
        }
        
        if sender.state == .began {
            isGesturing = true
        }
        
        if sender.state == .changed {
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Only scale x axis
            let scale = sender.scale
            sender.scale = 1.0
            lastScale = scale
            
            var point = sender.location(in: self)
            point = self.layer.convert(point, to: zoomLayer)
            point.x -= zoomLayer.bounds.midX  // zoomLayer anchorPoint is at center
            var transform = CATransform3DTranslate(zoomLayer.transform, point.x, 0.0, 0.0)
            transform = CATransform3DScale(transform, scale, 1.0, 1.0)
            transform = CATransform3DTranslate(transform, -point.x, 0.0, 0.0)
            zoomLayer.transform = transform
            let xTrans = zoomLayer.value(forKeyPath: "transform.translation.x")
            let xScale = zoomLayer.value(forKeyPath: "transform.scale.x") as! CGFloat
            CATransaction.commit()
            
        } else if (sender.state == .ended) {
            
            isGesturing = false
            
            let dataScale = dataRange.y - dataRange.x
            let xScale = 1 / dataScale
            
            let seriesRectFromZoomLayer = self.layer.convert(self.seriesRect, from: self.zoomLayer)
            let zlVisibleFrac = (self.seriesRect.width / seriesRectFromZoomLayer.width)
            let zlStartFrac = (self.seriesRect.origin.x - seriesRectFromZoomLayer.origin.x) / seriesRectFromZoomLayer.width
            
            let newDataRange = CGPoint(x: max(0.0, dataRange.x + (zlStartFrac / xScale)), y: min(1.0, dataRange.x + ((zlStartFrac + zlVisibleFrac) / xScale)))
            
            //NSLog("Pinch to [\(newDataRange.x):\(newDataRange.y)]")
            if newDataRange != self.dataRange && (newDataRange.y - newDataRange.x < 1.0) {
                // Zoomed in
                NSLog("Pinch to [\(newDataRange.x):\(newDataRange.y)]")
                self.dataRange = newDataRange
                clearStateCache()
                refreshGraph()
            } else if newDataRange != self.dataRange {
                // Zoomed all the way out
                resetDataRange()
                refreshGraph()
            } else {
                // Animate transform back to identity. No meaningful zoom happened (e.g: Just zoomed out 1x scale)
                zoomLayer.transform = CATransform3DIdentity
            }
        }
    }
    
    // Whether to fully draw every intermediate step
    // Because of sampling this doesn't look great yet
    
    var smoothPan = false
    
    func onPan(_ sender: UIPanGestureRecognizer) {
        if portraitMode {
            return
        }
        
        if sender.state == .began {
            isGesturing = true
        }
        
        let dataScale = dataRange.y - dataRange.x
        let xScale = 1 / dataScale
        let translation = sender.translation(in: self)
        let xTransNormalized = translation.x // / xScale
        
        let seriesRectFromZoomLayer = self.layer.convert(self.seriesRect, from: self.zoomLayer)
        let xTransRaw = self.seriesRect.origin.x - seriesRectFromZoomLayer.origin.x
        let xTrans = (xTransRaw / self.seriesRect.width) / xScale
        let dataRangeLeeway = (xTrans > 0) ? /* left */ 1.0 - dataRange.y : /* right */ dataRange.x
        let xTransNormal = min(dataRangeLeeway, xTrans)
        
        sender.setTranslation(CGPoint.zero, in: self)

        if sender.state == .changed {
            
            // Limit pan
            if xScale <= 1.0 ||                                                             // Not zoomed in
                (xTransNormalized > 0.0 && self.dataRange.x + xTransNormal <= 0.0) ||       // Panning beyond left bounds
                (xTransNormalized < 0.0 && self.dataRange.y + xTransNormal >= 1.0) {        // Panning beyond right bounds
                return
            }

            if (!smoothPan) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                zoomLayer.transform = CATransform3DTranslate(zoomLayer.transform, xTransNormalized, 0.0, 0.0)
                CATransaction.commit()
            } else {
                let xTransInDataRange = (translation.x / self.seriesRect.width) / xScale
                let newDataRange = CGPoint(x: max(0, self.dataRange.x - xTransInDataRange), y: min(1.0, self.dataRange.y - xTransInDataRange))
                if newDataRange != self.dataRange {
                    self.dataRange = newDataRange
                    refreshGraph()
                }
            }
            
        } else if (sender.state == .ended) {
            
            isGesturing = false

            let newDataRange = CGPoint(x: max(0, self.dataRange.x + xTransNormal), y: min(1.0, self.dataRange.y + xTransNormal))
            
            NSLog("Pan [\(dataRange) -> \(newDataRange)")

            if newDataRange != self.dataRange {
                self.dataRange = newDataRange
                refreshGraph()
            }
        }
    }
    
    func refreshGraph() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        zoomLayer.transform = CATransform3DIdentity
        
        resizeLayers()
        
        if let dataSource = self.dataSource {
            let dataCount = dataSource.getCount()
            if true { //stateCacheDataCount != dataCount {
                NSLog("CALayer - Caching data. \(dataCount) items, \(stateCache.count) in cache")
                // Assume that we're working with timeseries data so only need to update cache if size changes
                self.cacheState(dataSource: dataSource, rect: seriesRect)
                
                for (_, series) in self.series {
                    series.bindData(rect: seriesRect, graphView: self)
                }
            }
        }
        drawLayers()
        CATransaction.commit()
    }
    
    func drawLayers() {
        NSLog("Draw layers")
        drawLabels()
        //axisLabelLayer.display()
        zoomLayer.display()
        zoomLayer.sublayers?.forEach {
            $0.display()
            //NSLog("Draw zoomLayer sublayer \($0.name)")
        }
    } // willRotate, layoutSublayers,
    
    private func drawLabels() {
        NSLog("Draw axisLabelLayer in")
        
        for (_, series) in series {
            if series is SpeedSeries && series.drawMaxValLineWithAxisLabels {
                let maxValFrac = (series as! ValueSeries).getMaximumValueInfo().1
                if maxValFrac > 0 {
                    series.drawSeriesMaxVal(rect: seriesRect, root: layer, bgColor: bgColor.cgColor, maxVal: CGFloat(maxValFrac), portraitMode: portraitMode)
                }
            }
            series.drawAxisLabels(rect: seriesAxisRect, root: axisLabelLayer, numLabels: 5, bgColor: bgColor.cgColor)
        }
        
        if let _ = dataSource {
            drawTimeLabels(rect: timeLabelsRect, root: axisLabelLayer, numLabels: portraitMode ? 2: 3)
        }
//        drawZoomHint(rect: seriesRect, context: cgContext)
    }
    
    private func resetDataRange() {
        self.dataRange = CGPoint(x: 0.0, y: 1.0)
        clearStateCache()
    }
    
    private func clearStateCache() {
        stateCacheDataCount = 0
        stateCache.removeAll()
        stateXPosCache.removeAll()
    }
    
    private func cacheState(dataSource: GraphDataSource, rect: CGRect) {
        let dataSourceCount = dataSource.getCount()
        let dataCount = Int(CGFloat(dataSourceCount) * (dataRange.y - dataRange.x))
        let widthPtsPerData: CGFloat = 2
        let maxPoints = Int(rect.width / widthPtsPerData)
        let numPoints = min(dataCount, maxPoints)
        stateCache = [OneWheelState](repeating: OneWheelState(), count: numPoints)
        stateXPosCache = [CGFloat](repeating: 0.0, count: numPoints)
        let deltaX = rect.width / (CGFloat(numPoints))
        var x: CGFloat = rect.origin.x + deltaX
        var cacheIdx = 0
        let dataIdxstart = CGFloat(dataSourceCount) * dataRange.x
        var dataIdx: Int = Int(dataIdxstart)
        NSLog("CALayer - Caching \(numPoints)/\(dataCount) graph data by deltX \(deltaX)")
        for idx in 0..<numPoints  {
            
            let frac = CGFloat(idx) / CGFloat(numPoints)
            dataIdx = Int(dataIdxstart + (frac * CGFloat(dataCount)))
            if dataIdx >= dataSourceCount {
                break
            }
            
            let state = dataSource.getStateForIndex(index: dataIdx)
            
            stateCache[cacheIdx] = state
            stateXPosCache[cacheIdx] = x
            
            x += deltaX
            cacheIdx += 1
        }
        stateCacheDataCount = dataCount
        NSLog("CALayer - Cached \(stateCache.count)/\(dataSourceCount) graph data [\(dataRange.x)-\(dataRange.y)] [\(dataIdxstart)-\(dataIdx)] [\(CGFloat(dataIdxstart)/CGFloat(dataSourceCount))-\(CGFloat(dataIdx)/CGFloat(dataSourceCount))]")
    }
    
    func drawTimeLabels(rect: CGRect, root: CALayer, numLabels: Int) {
        NSLog("drawTimeLabels")
        
        if timeAxisLabels == nil {
            timeAxisLabels = [CATextLayer]()
        }
        
        while (timeAxisLabels!.count < numLabels) {
            let newLayer = CATextLayer()
            timeAxisLabels?.append(newLayer)
            root.addSublayer(newLayer)
        }

        let dataCount = dataSource!.getCount()
        
        if dataCount == 0 {
            return
        }
        
        let labelFont = UIFont.systemFont(ofSize: 14.0)
        
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        
        let labelSideMargin: CGFloat = 5
        for axisLabelIdx in 0..<numLabels {
            
            let axisLabelFrac: CGFloat = CGFloat(axisLabelIdx) / CGFloat(numLabels-1)
            let startIdx = Int(dataRange.x * CGFloat((dataCount - 1)))
            let state = dataSource!.getStateForIndex(index: min(dataCount - 1, Int(CGFloat(dataCount-1) * ((dataRange.y - dataRange.x) * axisLabelFrac)) + startIdx))
            
            let x: CGFloat = (rect.width * axisLabelFrac) + rect.origin.x
            let axisLabel = formatter.string(from: state.time)
            
            var labelRect = axisLabel.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [NSAttributedStringKey.font: labelFont], context: nil)
            var rectX = x - (labelRect.width / 2)
            let rectY = rect.height - labelSideMargin - labelRect.height
            
            let labelLayer = timeAxisLabels![axisLabelIdx]
            labelLayer.isHidden = false
            labelLayer.font = labelFont
            labelLayer.fontSize = labelFont.pointSize
            labelLayer.foregroundColor = UIColor.white.cgColor
            labelLayer.backgroundColor = bgColor.cgColor
            labelLayer.contentsScale = UIScreen.main.scale
            
            if axisLabelIdx == 0 {
                rectX = labelSideMargin + x
                labelLayer.alignmentMode = "left"
            } else if axisLabelIdx == numLabels - 1 {
                rectX = x - labelSideMargin - labelRect.width
                labelLayer.alignmentMode = "right"
            } else {
                labelLayer.alignmentMode = "center"
            }
            
            labelLayer.string = axisLabel
            
            labelRect = CGRect(x: rectX, y: rectY, width: labelRect.width, height: labelRect.height)
            labelLayer.frame = labelRect
            labelLayer.display()
            
            NSLog("Drawing time axis label \(axisLabel)")
        }
        
        for i in numLabels..<timeAxisLabels!.count {
            timeAxisLabels![i].isHidden = true
            NSLog("Hiding time axis label \(timeAxisLabels![i].string)")
        }
    }
    
    func drawZoomHint(rect: CGRect, context: CGContext) {
        NSLog("drawZoomHint")
        if dataRange.y - dataRange.x == 1.0 {
            // Don't draw zoom hint when zoomed all the way out
            return
        }
        
        let yPad: CGFloat = 0.0
        let yHeight: CGFloat = 3.0
        
        let zoomStart = rect.origin.x + (dataRange.x * rect.width)
        let zoomEnd = zoomStart + ((dataRange.y - dataRange.x) * rect.width)
        
        let rt = CGRect(x: zoomStart, y: yPad, width: zoomEnd - zoomStart, height: yHeight)
        
        context.setFillColor(zoomHintColor)
        context.fill(rt)
    }

    func addSeries(newSeries: Series) {
        if self.dataSource != nil {
            series[newSeries.name] = newSeries
            //addSeriesSubLayer(series: newSeries) BAD_ACCESS
            newSeries.requestLayerSetup(root: self.zoomLayer, frame: seriesRect, graphView: self)
        } else {
            NSLog("Cannot add series before a datasource is set")
        }
    }
 
    class BooleanSeries : Series, CALayerDelegate {
        
        private var path: CGPath? = nil
        private var layer: CAShapeLayer? = nil
        
        override func setupLayers(root: CALayer, frame: CGRect, graphView: OneWheelGraphView) {
            let scale = UIScreen.main.scale
            
            let l = CAShapeLayer()
            l.fillColor = color
            l.contentsScale = scale
            l.frame = frame
            root.addSublayer(l)
            self.layer = l
        }
        
        override func resizeLayers(frame: CGRect, graphView: OneWheelGraphView) {
            let midPt = CGPoint(x: frame.midX, y: frame.midY)
            
            layer?.bounds = frame
            layer?.position = midPt
            
            if let path = self.path, !path.boundingBox.isEmpty, let layer = self.layer {
                
                let newPath = createPath(rect: frame, graphView: graphView)
                animateShapeLayerPath(shapeLayer: layer, newPath: newPath)
            }
        }
        
        override func bindData(rect: CGRect, graphView: OneWheelGraphView) {
            layer?.setNeedsDisplay()
            
            if let layer = self.layer {
                let path = createPath(rect: rect, graphView: graphView)
                layer.path = path
            }
        }
        
        private func createPath(rect: CGRect, graphView: OneWheelGraphView) -> CGPath {
            let path = CGMutablePath()
            forEachData(rect: rect, graphView: graphView) { (x, state) -> CGFloat in
                let normVal = CGFloat(getNormalizedVal(state: state))
                if normVal == 1.0 {
                    let errorRect = CGRect(x: lastX, y: rect.origin.y, width: (x-lastX), height: rect.height)
                    path.addRect(errorRect)
                }
                return rect.origin.y
            }
            return path
        }
    }
    
    class ValueSeries : Series {
        
        private var shapeLayer: CAShapeLayer? = nil
        private var bgLayer: CAGradientLayer? = nil
        private var bgMaskLayer: CAShapeLayer? = nil
        
        override func setupLayers(root: CALayer, frame: CGRect, graphView: OneWheelGraphView) {
            let scale = UIScreen.main.scale
            
            if gradientUnderPath {
                let bgM = CAShapeLayer()
                bgM.contentsScale = scale
                bgM.frame = frame
                bgM.fillColor = color
                self.bgMaskLayer = bgM
                
                let bg = CAGradientLayer()
                bg.contentsScale = scale
                bg.frame = frame
                bg.colors = [color.copy(alpha: 0.9)!, color.copy(alpha: 0.0)!]
                bg.startPoint = CGPoint(x: 0.0, y: 0.0)
                bg.endPoint = CGPoint(x: 0.0, y: 1.0)
                bg.locations = [0.0, 1.0]
                bg.mask = bgM
                
                root.addSublayer(bg)
                self.bgLayer = bg
            }
            
            let sl = CAShapeLayer()
            sl.miterLimit = 0
            sl.contentsScale = scale
            sl.frame = frame
            sl.fillColor = UIColor.clear.cgColor
            sl.lineWidth = 3.0
            sl.strokeColor = color
            root.addSublayer(sl)
            self.shapeLayer = sl
        }
        
        override func resizeLayers(frame: CGRect, graphView: OneWheelGraphView) {
            let midPt = CGPoint(x: frame.midX, y: frame.midY)
            
            shapeLayer?.bounds = frame
            shapeLayer?.position = midPt
            
            bgMaskLayer?.bounds = frame
            bgMaskLayer?.position = midPt
            
            bgLayer?.bounds = frame
            bgLayer?.position = midPt
            
            if let shapeLayer = self.shapeLayer {

                let newPath = createPath(rect: frame, graphView: graphView)
                animateShapeLayerPath(shapeLayer: shapeLayer, newPath: newPath)
             
                if gradientUnderPath, let bgMaskLayer = self.bgMaskLayer {
                    let newMaskPath = closePath(path: newPath, rect: frame)
                    animateShapeLayerPath(shapeLayer: bgMaskLayer, newPath: newMaskPath)
                    bgLayer?.mask = bgMaskLayer
                }
            }
        }
        
        override func bindData(rect: CGRect, graphView: OneWheelGraphView) {
            if let shapeLayer = self.shapeLayer {
                let path = createPath(rect: rect, graphView: graphView)
                shapeLayer.path = path
                
                if gradientUnderPath {
                    bgMaskLayer?.path = closePath(path: path, rect: rect)
                    bgLayer?.mask = bgMaskLayer
                }
            }
        }
        
        // Subclass overrides
        public func getMaximumValueInfo() -> (Date, Float) {
            return (Date.distantFuture, 0.0)
        }
        
        private func closePath(path: CGPath, rect: CGRect) -> CGPath {
            let maskPath = path.mutableCopy()!
            maskPath.addLine(to: CGPoint(x: lastX, y: rect.height))
            maskPath.addLine(to: CGPoint(x: rect.origin.x, y: rect.height))
            maskPath.closeSubpath()
            return maskPath
        }
        
        private func createPath(rect: CGRect, graphView: OneWheelGraphView) -> CGMutablePath {
            NSLog("CALayer - ValueSeries createPath \(self.name) in \(rect)")
            
            // TODO : Guard graphView, series etc.
            let path = CGMutablePath()
            var didInitPath = false
            
            forEachData(rect: rect, graphView: graphView) { (x, state) -> CGFloat in
                let normVal = CGFloat(getNormalizedVal(state: state))
                let y = ((1.0 - normVal) * rect.height) + rect.origin.y
                
                if !didInitPath {
                    didInitPath = true
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                
                return y
            }
            NSLog("CALayer - createdPath \(self.name) in \(path.boundingBox)")

            return path
        }
    }
    
    class Series : NSObject {
        
        enum AxisLabelType {
            case None
            case Left
            case Right
        }
        
        let name: String
        let color: CGColor
        let evaluator: SeriesEvaluator
        let labelType: AxisLabelType
        let gradientUnderPath: Bool
        
        var drawMaxValLineWithAxisLabels = false
        
        var min = 0.0
        var max = 0.0
        
        var lastX: CGFloat = 0.0
        var lastY: CGFloat = 0.0
        
        private let shapeAnimateDurationS = 0.100
        
        // Drawing
        internal var didSetupLayers = false // private set
        internal var axisLabelLayers: [CATextLayer]? = nil
        internal var maxValLayer: CAShapeLayer? = nil
        internal var maxValLabel: CATextLayer? = nil
        
        init(name: String, color: CGColor, labelType: AxisLabelType, gradientUnderPath: Bool, evaluator: SeriesEvaluator) {
            self.name = name
            self.color = color
            self.labelType = labelType
            self.gradientUnderPath = gradientUnderPath
            self.evaluator = evaluator
        }
        
        func requestLayerSetup(root: CALayer, frame: CGRect, graphView: OneWheelGraphView) {
            if didSetupLayers {
                return
            }
            didSetupLayers = true
            
            setupLayers(root: root, frame: frame, graphView: graphView)
        }
        
        internal func setupLayers(root: CALayer, frame: CGRect, graphView: OneWheelGraphView) {
            // Subclass override
        }
        
        internal func resizeLayers(frame: CGRect, graphView: OneWheelGraphView) {
            // Subclass override
        }
        
        func bindData(rect: CGRect, graphView: OneWheelGraphView) {
            // Subclass override
        }
        
        // Return the normalized value at the given index.
        // returns a value between [0, 1]
        func getNormalizedVal(state: OneWheelState) -> Double {
            let val = evaluator.getValForState(state: state)
            return (val / (max - min))
        }
        
        internal func forEachData(rect: CGRect, graphView: OneWheelGraphView, onData: (CGFloat, OneWheelState) -> CGFloat) {
            lastX = 0
            lastY = rect.height
            
            for cacheIdx in 0..<graphView.stateCache.count {
                let state = graphView.stateCache[cacheIdx]
                let x = graphView.stateXPosCache[cacheIdx]
                
                let y = onData(x, state)

                lastX = x
                lastY = y
            }
        }
        
        internal func animateShapeLayerPath(shapeLayer: CAShapeLayer, newPath: CGPath) {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = shapeLayer.path
            animation.toValue = newPath
            animation.duration = shapeAnimateDurationS
            animation.timingFunction =  CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
            shapeLayer.add(animation, forKey: "path")
            shapeLayer.path = newPath
        }
        
        internal func animateLayerPosition(layer: CALayer, newPos: CGPoint) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = layer.position
            animation.toValue = newPos
            animation.duration = shapeAnimateDurationS
            animation.timingFunction =  CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
            layer.add(animation, forKey: "position")
            layer.position = newPos
            CATransaction.commit()
        }
        
        func drawAxisLabels(rect: CGRect, root: CALayer, numLabels: Int, bgColor: CGColor) {
            if labelType == AxisLabelType.None {
                for layer in axisLabelLayers ?? [] {
                    layer.isHidden = true
                }
                return
            }
            
            if axisLabelLayers == nil {
                axisLabelLayers = [CATextLayer]()
            }
            
            while (axisLabelLayers!.count < numLabels) {
                let newLayer = CATextLayer()
                axisLabelLayers?.append(newLayer)
                root.addSublayer(newLayer)
            }
            
            let labelFont = UIFont.systemFont(ofSize: 14.0)
            
            var labelIdx = 0
            let labelSideMargin: CGFloat = 5
            let x: CGFloat = (labelType == AxisLabelType.Left) ? CGFloat(labelSideMargin) : rect.width - labelSideMargin
            for axisLabelVal in stride(from: min, through: max, by: (max - min) / Double(numLabels)) {
                // TODO : Re-evaluate, but for now don't draw 0-val label
                if axisLabelVal == min {
                    continue
                }
                
                let y = CGFloat(1.0 - ((axisLabelVal - min) / (max - min))) * rect.height
                let axisLabel = printAxisVal(val: axisLabelVal)
                
                let labelLayer = axisLabelLayers![labelIdx]
                labelLayer.isHidden = false
                labelLayer.font = labelFont
                labelLayer.fontSize = labelFont.pointSize
                labelLayer.alignmentMode = (labelType == AxisLabelType.Left) ? "left" : "right"
                labelLayer.foregroundColor = color
                labelLayer.backgroundColor = bgColor
                labelLayer.string = axisLabel
                labelLayer.contentsScale = UIScreen.main.scale
                
                var labelRect = axisLabel.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [NSAttributedStringKey.font: labelFont], context: nil)
                let rectX = (labelType == AxisLabelType.Right) ? x - labelRect.width : x
                labelRect = CGRect(x: rectX, y: y, width: labelRect.width, height: labelRect.height)
                labelLayer.frame = labelRect
                labelLayer.display()
                NSLog("Axis label \(axisLabel) at \(labelLayer.position)")
                labelIdx += 1

                // Assumes RTL language : When positioning left-flowing text on the right side, need to move our start point left by the text width
            }
            
            for i in labelIdx..<axisLabelLayers!.count {
                axisLabelLayers![i].isHidden = true
            }
        }
        
        func drawSeriesMaxVal(rect: CGRect, root: CALayer, bgColor: CGColor, maxVal: CGFloat, portraitMode: Bool) {
            NSLog("drawSeriesMaxVal")
            
            if (maxValLayer == nil) {
                maxValLayer = CAShapeLayer()
                root.addSublayer(maxValLayer!)
            }
            if (maxValLabel == nil) {
                maxValLabel = CATextLayer()
                root.addSublayer(maxValLabel!)
            }
            
            maxValLayer!.frame = rect
            maxValLabel!.frame = rect
            
            let labelSideMargin: CGFloat = portraitMode ? 60 : 10  // In portrait mode we let the seriesRect extend behind axis labels
            let maxYPos: CGFloat = ((1.0 - maxVal) * rect.height) + rect.origin.y
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: maxYPos))
            path.addLine(to: CGPoint(x: rect.width, y: maxYPos))
            // TODO : Line properties
            maxValLayer!.path = path
            maxValLayer!.strokeColor = color.copy(alpha: 0.7)
            maxValLayer!.lineWidth = 1.0
            
            let maxLabel = String(format: "%.1f", (Double(maxVal) * max))
            
            let labelFont = UIFont.systemFont(ofSize: 12.0)
            
            var labelRect = maxLabel.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [NSAttributedStringKey.font: labelFont], context: nil)
            labelRect = CGRect(x: rect.minX + labelSideMargin, y: maxYPos - (labelRect.height / 2), width: labelRect.width, height: labelRect.height)

            maxValLabel!.frame = labelRect
            maxValLabel!.isHidden = false
            maxValLabel!.font = labelFont
            maxValLabel!.fontSize = labelFont.pointSize
            maxValLabel!.alignmentMode = "left"
            maxValLabel!.foregroundColor = color
            maxValLabel!.backgroundColor = bgColor
            maxValLabel!.string = maxLabel
            maxValLabel!.contentsScale = UIScreen.main.scale
        }
        
        func printAxisVal(val: Double) -> String {
            return "\(val)"
        }
    }
    
    class ControllerTempSeries : ValueSeries, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, labelType: AxisLabelType.None, gradientUnderPath: false, evaluator: self)
            max = 120 // TODO: Figure out reasonable max temperatures
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return Double(state.controllerTemp)
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))°F"
        }
    }
    
    class MotorTempSeries : ValueSeries, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, labelType: AxisLabelType.Right, gradientUnderPath: false, evaluator: self)
            max = 120 // TODO: Figure out reasonable max temperatures
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return Double(state.motorTemp)
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))°F"
        }
    }
    
    class SpeedSeries : ValueSeries, SeriesEvaluator {
        
        let rideLocalData: RideLocalData

        init(name: String, color: CGColor, rideData: RideLocalData) {
            self.rideLocalData = rideData
            
            super.init(name: name, color: color, labelType: AxisLabelType.Left, gradientUnderPath: true, evaluator: self)
            max = 20.0 // Current world record is ~ 27 MPH
            
            // Draw max speed line
            self.drawMaxValLineWithAxisLabels = true
        }
        
        public override func getMaximumValueInfo() -> (Date, Float) {
            return (rideLocalData.getMaxRpmDate() ?? Date.distantFuture, Float(rpmToMph(Double(rideLocalData.getMaxRpm())) / max))
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return state.mph()
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))MPH"
        }
    }
    
    class BatterySeries : ValueSeries, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, labelType: AxisLabelType.Right, gradientUnderPath: false, evaluator: self)
            max = 100.0
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return Double(state.batteryLevel)
        }
        
        override func printAxisVal(val: Double) -> String {
            return "\(Int(val))%"
        }
    }
    
    class ErrorSeries : BooleanSeries, SeriesEvaluator {
        
        init(name: String, color: CGColor) {
            super.init(name: name, color: color, labelType: AxisLabelType.None, gradientUnderPath: false, evaluator: self)
            max = 1.0
        }
        
        func getValForState(state: OneWheelState) -> Double {
            return (state.mph() > 1.0) && ((!state.footPad1 && !state.footPad2) || (!state.riderPresent)) ? 1.0 : 0.0
        }
    }
}

protocol GraphDataSource {
    func getCount() -> Int
    func getStateForIndex(index: Int) -> OneWheelState
}

protocol SeriesEvaluator {
    func getValForState(state: OneWheelState) -> Double
}
