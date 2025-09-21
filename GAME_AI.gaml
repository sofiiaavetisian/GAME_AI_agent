/**
* Name: ai hockey
* Air Hockey Game 
* Author: sofiiaavetisian
*/

model hockey

global {
    
    //REAL-WORLD DIMENTIONS FOR LAB SETUP
    geometry shape <- rectangle(137.5, 68.5); //, by  each square in the floor is 50 cm and so we have a predefined area of 7 by 4 squares
    point correction <- {-38.33982050418854, 72.43500351905823, 0}; //['71.20521068572998','-106.8634033203125'];
    list<geometry> arena_keystone <- [{0.0736697534742366,0.23169516447101535,0.0}, {0.0675060826301559,1.0367573972528539,0.0}, {0.8445979162363061,1.011437353862544,0.0},{0.8474850121913879,0.23125704030401106,0.0} ];
    float grid_width <- shape.width;
    float grid_height <- shape.height;
    
    // AGENT PORT VARIABLES 
    int port <- 9876;
    string url <- "localhost";
    int number_of_agents <- 2;
    int base_id <- 2;

    // GAME MODE
    bool ai_opponent <- true;
    
    bool show_puck <- true;
    bool show_border <- false;
    bool show_board <- true;
    
    // OFFSET VARIABLES -0.5, -1.5, -2.0, -4.5
    float x_offset_min <- -0.5;
    float x_offset_max <- -1.5;
    float y_offset_min <- -2.0;
    float y_offset_max <- -4.5;
    
    // GAME VARIABLES
    bool game_start <- false;
    bool first <- true;
    bool slow <- false;
    int p1_score <- 0;
    int p2_score <- 0;
    int win_score <- 10;
    
    float full_rotation_threshold <- 90.0;
    float base_speed <- 2.0;
    float collision_radius <- 3.0;
    
    point reset_trigger_spot1 <- {grid_width / 4, grid_height / 2, 0.01};
    point reset_trigger_spot2 <- {3 * grid_width / 4, grid_height / 2, 0.01};
    geometry goal1 <- rectangle(7, 22) at_location {0, grid_height / 2};
    geometry goal2 <- rectangle(7, 22) at_location {grid_width, grid_height / 2};

    init {
        int humans_to_create <- number_of_agents;
        if (ai_opponent) { humans_to_create <- 1; }
        
        create player number: humans_to_create {
           do connect to: url protocol: "udp_server" port: port + base_id;
           base_id <- base_id + 1;
           self.name <- string(base_id);
           self.id <- base_id; // human gets id=3 → left side
           self.color <- rnd_color(255);
        }

        if (ai_opponent) {
            create ai_player number: 1 {
                self.id <- 5;         
                self.name <- "AI";
                self.color <- #blue;
            }
        }

        create puck;
    }
}

species game_object parallel: true skills: [moving, network] {
    float rot;
    point target_location;
    int size <- 3;
    rgb color;
    int id;
    
    bool is_within_grid(point pos) {
        return pos.x >= 0 and pos.x <= grid_width and pos.y >= 0 and pos.y <= grid_height;
    }
    
    bool is_within_side(point pos) {
        if (even(id)) {
            return pos.x <= grid_width / 2;
        } else {
            return pos.x >= grid_width / 2;
        }
    }
    
    action reset_game { 
        p1_score <- 0;
        p2_score <- 0;

        game_start <- true;
        first <- false;

        ask puck { 
            do reset_puck; 
        }
    }
    
    action calculate_offset {
        float offset_x;

        if (self.location.x >= 0) {
            offset_x <- x_offset_min + (self.location.x / grid_width) * (x_offset_max - x_offset_min);
        } else {
            offset_x <- x_offset_min + (self.location.x / -grid_width) * (x_offset_max - x_offset_min);
        }

        float offset_y;
        if (self.location.y >= 0) {
            offset_y <- y_offset_min + (self.location.y / grid_height) * (y_offset_max - y_offset_min);
        } else {
            offset_y <- y_offset_min + (self.location.y / -grid_height) * (y_offset_max - y_offset_min);
        }
        return {offset_x, offset_y, 0};
    }
    
    aspect default {
        draw circle(size) at: self.location color: color rotate: rot anchor: #center;
    }
    
    aspect player {
        point offset <- calculate_offset();

        draw circle(size) at: (self.location + offset) color: color rotate: rot anchor: #center;
    }
}

// HUMAN PLAYER ALWAYS ON TEH RIGHT SIDE
species player parent: game_object {
    float rotation_accumulator <- 0.0;

    init {
        self.location <- {3 * grid_width / 4, grid_height / 2, 0};
    }

    bool is_within_side(point pos) {
        return pos.x >= grid_width / 2;
    }

    reflex fetch when: has_more_message() {
        loop while: has_more_message() {
            message msg <- fetch_message();
            list<string> coords <- msg.contents regex_matches("[-+]?\\d*\\.?\\d+");

            target_location <- {float(coords[1]) + correction.y, float(coords[0]) - correction.x, 0};

            float current_rotation <- float(coords[3]) * -100;
            rotation_accumulator <- rotation_accumulator + abs(current_rotation - rot);
            rot <- current_rotation;

            if (is_within_grid(target_location) and is_within_side(target_location)) {
                self.location <- target_location;
            }
        }
    }

    reflex reset when: !game_start {
        if (!game_start and (self.location distance_to reset_trigger_spot1 <= 3.0 or self.location distance_to reset_trigger_spot2 <= 3.0)) {
            if (rotation_accumulator >= full_rotation_threshold) {
                do reset_game;
                rotation_accumulator <- 0.0;
            }
        } else {
            rotation_accumulator <- 0.0;
        }
    }
}

species ai_player parent: game_object {
    float ai_step <- base_speed;
    float margin  <- 1.0;

    init {
        
        //LEFT SIDE OF THE FIELD
        self.location <- {grid_width / 4, grid_height / 2, 0};
        self.name <- "AI";
        self.color <- #blue;
    }

    bool is_within_side(point pos) {
        return pos.x <= grid_width / 2;
    }

    reflex play when: game_start and every(0.1#s) {
        puck pk <- one_of(puck);

        float half <- grid_width / 2.0;

        point target;
        float defend_x <- 6.0;

        if (pk.location.x <= half) {
            float chase_x <- pk.location.x + 1.5;
            target <- {chase_x, pk.location.y, 0};
        } else {
            target <- {defend_x, pk.location.y, 0};
        }

        target.x <- min(target.x, half - margin);
        target.y <- max(0.0, min(grid_height, target.y));

        float dx <- target.x - self.location.x;
        float dy <- target.y - self.location.y;
        float d  <- sqrt(dx*dx + dy*dy);

        if (d > 0.0) {
            float ux <- dx / d;
            float uy <- dy / d;
            float step <- min(ai_step, d);
            point np <- { self.location.x + ux * step, self.location.y + uy * step, 0 };
            if (is_within_grid(np) and is_within_side(np)) { 
                self.location <- np; 
            }
        }
    }

    aspect player {
        point offset <- calculate_offset();
        draw circle(size) at: (self.location + offset) color: color rotate: rot anchor: #center;
    }
}

species puck parent: game_object {
    rgb color <- #blue;
    float speed <- base_speed;
    float direction_x <- rnd(-1.0, 1.0);
    float direction_y <- rnd(-1.0, 1.0);
    bool is_resetting <- false;
    
    init {
        self.location <- {grid_width / 2, grid_height / 2, 0};
    }

    reflex init {
        float magnitude <- sqrt(direction_x * direction_x + direction_y * direction_y);
        if (direction_x != 0.0 and direction_y != 0.0) {
            direction_x <- direction_x / magnitude;
            direction_y <- direction_y / magnitude;
        }
    }

    reflex move when: game_start and every(0.1#s) {
        float new_x <- self.location.x + direction_x * speed;
        float new_y <- self.location.y + direction_y * speed;

        if (new_x < 0 or new_x > grid_width) {
            direction_x <- -direction_x;
            new_x <- self.location.x + direction_x * speed;
        }
        if (new_y < 0 or new_y > grid_height) {
            direction_y <- -direction_y;
            new_y <- self.location.y + direction_y * speed;
        }
        
        self.location <- {new_x, new_y, self.location.z};
        do check_goal;
    }
    
    reflex player_collision when: every(0.1#s) {
        ask player {
            if ((self.location distance_to myself.location) <= collision_radius + myself.size) {
                float dx <- myself.location.x - self.location.x;
                float dy <- myself.location.y - self.location.y;
                float magnitude <- sqrt(dx * dx + dy * dy);
                
                myself.direction_x <- dx / magnitude;
                myself.direction_y <- dy / magnitude;
                myself.location <- myself.location + {myself.direction_x, myself.direction_y, 0} * 0.1;
                
                if (myself.speed < base_speed * 1.5) { 
                    myself.speed <- myself.speed + 0.05; 
                }
            }
            else if ((myself.speed > base_speed * 2) and slow) {
                myself.speed <- myself.speed - 0.001;
          }
        }
    }

    reflex ai_collision when: every(0.1#s) {
        ask ai_player {
            if ((self.location distance_to myself.location) <= collision_radius + myself.size) {
                float dx <- myself.location.x - self.location.x;
                float dy <- myself.location.y - self.location.y;
                float magnitude <- sqrt(dx * dx + dy * dy);
                myself.direction_x <- dx / magnitude;
                myself.direction_y <- dy / magnitude;
                myself.location <- myself.location + {myself.direction_x, myself.direction_y, 0} * 0.1;
                if (myself.speed < base_speed * 1.5) { myself.speed <- myself.speed + 0.05; }
            }
            else if ((myself.speed > base_speed * 2) and slow) {
                myself.speed <- myself.speed - 0.001;
            }
        }
    }

    action check_goal {
        if (self.location distance_to goal1 <= 2) {
            p2_score <- p2_score + 1;
            do reset_puck;
            if (p2_score >= win_score) { 
                game_start <- false; 
                do stop_puck; 
        } 

        } else if (self.location distance_to goal2 <= 2) {
            p1_score <- p1_score + 1;
            do reset_puck;
            if (p1_score >= win_score) {
                game_start <- false; 
                do stop_puck; 
            } 
        }
    }
    
    action reset_puck {
        self.location <- {grid_width / 2, grid_height / 2, 0};
        direction_x <- rnd(-1.0, 1.0);
        direction_y <- rnd(-1.0, 1.0);
        float magnitude <- sqrt(direction_x * direction_x + direction_y * direction_y);
        direction_x <- direction_x / magnitude;
        direction_y <- direction_y / magnitude;
        speed <- base_speed;
    }
    
    action stop_puck {
        self.location <- {grid_width / 2, grid_height / 2, 0};
        direction_x <- 0.0;
        direction_y <- 0.0;
        speed <- 0.0;
    }
    
    aspect default {
        if (show_puck) {
            draw circle(size) color: color rotate: rot anchor: #center;
        }
    }
}

grid space cell_width: 15.5 cell_height: 15.5 parallel: true { 
    aspect dev {
        if (show_border){ 
            draw shape color: #white border: #green width: 1; 
        }
        else { 
            draw shape color: #white border: #white width: 1; 
        }
    }
}

experiment hockey type: gui virtual: true{

    // EXPERIMENT PARAMETERS 
    parameter "URL" var: url <- url among: ["10.205.3.55", "127.0.0.1","10.205.3.9", "10.205.3.82", "localhost"] category: "Connection Variables";
    parameter "PORT" var: port <- port among: [9876, 1234, 53408] category: "Connection Variables";
    parameter "Number of Players" var: number_of_agents <- number_of_agents min: 0 max: 10 category: "Connection Variables";
    parameter "UMH Base ID" var: base_id <- base_id min: 0 max: 10 category: "Connection Variables";
    
    // DISPLAY PARAMETERS
    parameter "Show Grid" var: show_border <- show_border category: "Display Options";
    parameter "Puck" var: show_puck <- show_puck category: "Display Options";
    parameter "Show Board" var: show_board <- show_board category: "Display Options";
    
    // OFFSET PARAMETERS
    parameter "X Offset Minimum" var: x_offset_min <- x_offset_min category: "Offset";
    parameter "X Offset Maximum" var: x_offset_max <- x_offset_max category: "Offset";
    parameter "Y Offset Minimum" var: y_offset_min <- y_offset_min category: "Offset";
    parameter "Y Offset Maximum" var: y_offset_max <- y_offset_max category: "Offset";
    
    // GAME PARAMETERS
    parameter "Puck Speed" var: base_speed <- base_speed min: 0.01 max: 10.0 category: "Game Options";
    parameter "De-acceleration" var: slow <- slow category: "Game Options";
    parameter "Collision Radius" var: collision_radius <- collision_radius min: 0.01 max: 10.0 category: "Game Options";
    parameter "Win Score Amount" var: win_score <- win_score min: 1 max: 100 category: "Game Options";
    parameter "Reset Rotation Value" var: full_rotation_threshold <- full_rotation_threshold min: 1.0 max: 360.0 category: "Game Options";
    parameter "AI Opponent (PvAI)" var: ai_opponent <- ai_opponent category: "Game Options";
    
    output {
        display default type: opengl toolbar: false fullscreen: 1 keystone:arena_keystone virtual: true {
            species puck position: {0, 0, 0.01};
            species player position: {0, 0, 0.01} aspect: player; 
            species ai_player position: {0, 0, 0.01} aspect: player;
        }
    }
}

experiment Main parent: hockey type: gui {
    output{
        monitor main value: cycle refresh: every(0.01#cycle);
        display main_display parent: default fullscreen: 1  {
            species space position: {0, 0, -0.01} aspect: dev;
            graphics game {
                if (show_board) {
                    draw shape color: #white border: #grey width: 8;             
                    draw line([{(grid_width / 2), 0}, {(grid_width / 2), grid_height}]) color: #red width: 8;             
                    draw circle(5) at: {(grid_width / 2), (grid_height / 2)} color: #red;        
                    draw rectangle(7, 22) at: {0, grid_height / 2} color: #red width: 3;
                    draw rectangle(7, 22) at: {grid_width, grid_height / 2} color: #red width: 3;                         
                    draw string(p1_score) + " : " + string(p2_score) at: {(grid_width / 2), (grid_height / 2) - 30} font:font("Arial", 35, #bold+#italic) color:#black anchor: #center;                                        
                }
                if (first) {
                    draw "Move to the squares and spin to start playing!" at: {(grid_width / 2), (grid_height / 2) - 15} font:font("Arial", 25, #bold) color:#green anchor: #center;
                }
                if (!game_start) {
                    if (p1_score >= win_score) {
                        draw "Human Wins!" at: {(grid_width / 2), (grid_height / 2) - 15} font:font("Arial", 35, #bold) color:#red anchor: #center;
                    } else if (p2_score >= win_score) {
                        draw "AI Wins!" at: {(grid_width / 2), (grid_height / 2) - 15} font:font("Arial", 35, #bold) color:#blue anchor: #center;
                    }
                    draw square(10) at: reset_trigger_spot1 color: #black anchor: #center;
                    draw "Start" at: reset_trigger_spot1 font:font("Arial", 25, #bold) color: #white anchor: #center;
                    draw square(10) at: reset_trigger_spot2 color: #black anchor: #center;
                    draw "Start" at: reset_trigger_spot2 font:font("Arial", 25, #bold) color: #white anchor: #center;
                    }   
                }
            event "r" { 
                ask player {do reset_game;} 
            }
        }
    }
}
experiment Benchmarking parent: Main type: gui benchmark: true {}
