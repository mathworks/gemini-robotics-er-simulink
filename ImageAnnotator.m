classdef ImageAnnotator
% Static drawing helpers for the reasoners' annotated artifact frames.

    properties (Constant, Access = private)
        % CoordScale - Range model coordinates are normalized to.
        CoordScale = 1000
    end

    methods (Static)
        function annotated = drawPlan(image, plan)
            % Draw a red pick dot + "#<order> <label>" per plan item and, when it has a drop point, a pick->drop arrow and a green drop dot (normalized [x y] 0-1000 -> pixels).
            annotated = image;
            if isempty(plan)
                return
            end
            [imageHeight, imageWidth, ~] = size(image);
            radius = ImageAnnotator.markerRadius(imageWidth, imageHeight);
            for k = 1:numel(plan)
                pickPixel = ImageAnnotator.normalizedToPixel(plan(k).center_2d, imageWidth, imageHeight);
                order = plan(k).pick_priority;
                if order < 1
                    order = k;
                end
                label = strtrim("#" + order + " " + plan(k).label);
                if ~isempty(plan(k).drop_center_2d)
                    dropPixel = ImageAnnotator.normalizedToPixel(plan(k).drop_center_2d, imageWidth, imageHeight);
                    annotated = insertShape(annotated, "line", ...
                        [pickPixel, dropPixel], Color="yellow", LineWidth=2);
                    annotated = ImageAnnotator.drawArrowHead(annotated, pickPixel, dropPixel);
                    annotated = insertShape(annotated, "filled-circle", ...
                        [dropPixel, radius], Color="green", Opacity=1);
                end
                annotated = insertShape(annotated, "filled-circle", ...
                    [pickPixel, radius], Color="red", Opacity=1);
                annotated = insertText(annotated, pickPixel + [radius + 2, -(radius + 2)], label, ...
                    FontSize=14, BoxColor="white", TextColor="black", BoxOpacity=0.6);
            end
        end

        function annotated = drawTaskBanner(image, task)
            % Overlay the task prompt as a wrapped banner across the top of the image.
            annotated = image;
            task = strtrim(task);
            if strlength(task) == 0
                return
            end
            imageWidth = size(image, 2);
            fontSize   = max(12, round(imageWidth * 0.018)) + 2;
            % Wrap to roughly the image width (~1.8 chars per font pixel of width).
            charsPerLine = max(20, floor(imageWidth / (fontSize * 0.6)));
            wrapped = string(textwrap({char(task)}, charsPerLine));
            banner  = strjoin(wrapped, newline);
            % Anchor the banner box at the top-center of the image.
            annotated = insertText(annotated, [round(imageWidth / 2), 0], banner, ...
                FontSize=fontSize, BoxColor="black", TextColor="white", ...
                BoxOpacity=0.6, AnchorPoint="CenterTop");
        end

        function annotated = drawVerdict(image, verify)
            % Draw a pass/fail banner (green PASS / red FAIL) plus the diagnostics text.
            if verify.pass
                banner = "PASS";
                color  = "green";
            else
                banner = "FAIL";
                color  = "red";
            end
            annotated = insertText(image, [10, 10], banner + ": " + verify.diagnostics, ...
                FontSize=14, BoxColor=color, TextColor="white", BoxOpacity=0.7);
        end
    end

    methods (Static, Access = private)
        function annotated = drawArrowHead(image, fromPixel, toPixel)
            % Draw a small V arrow head at toPixel pointing away from fromPixel.
            annotated = image;
            direction = toPixel - fromPixel;
            norm = hypot(direction(1), direction(2));
            if norm < 1
                return
            end
            unit = direction / norm;
            perp = [-unit(2), unit(1)];
            headLength = 12;                        % fixed small arrow head (px)
            base  = toPixel - unit * headLength;
            left  = base + perp * headLength * 0.5;
            right = base - perp * headLength * 0.5;
            annotated = insertShape(annotated, "line", ...
                [left, toPixel, right, toPixel], Color="yellow", LineWidth=2);
        end

        function radius = markerRadius(imageWidth, imageHeight)
            % Dot radius in pixels, scaled to the image (min 4 px).
            radius = max(4, round(min(imageWidth, imageHeight) * 0.008));
        end

        function pixel = normalizedToPixel(point, imageWidth, imageHeight)
            % Normalized [x y] (0-1000) -> rounded pixel [x y] in the target image.
            pixel = [ ...
                round(point(1) * imageWidth  / ImageAnnotator.CoordScale), ...
                round(point(2) * imageHeight / ImageAnnotator.CoordScale)];
        end
    end
end
