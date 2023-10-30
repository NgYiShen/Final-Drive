extends VehicleBody3D

############################################################
@export var MaxEngineForce = 3200.0 # Dev car, normal is 320
@export var MaxBrakeForce = 100.0
@export var MaxRPM = 7200.0
@export var MaxSteer = 0.6 # in radians

#@export var GearRatio = [3.214, 1.925, 1.302, 1.000, 0.752]
@export var GearRatio = [3.5, 2.3, 2.0, 1.7, 1.4]
@export var ReverseRatio = -3.369
@export var FinalDriveRatio = 4.111

@export var HitPoint = 1000.0

const IdleRPM = 1100.0
@export var PowerCurve: Curve
@export var DragCoefficient = 0.3
@export var Downforce = 0
############################################################
var current_gear = 0 
var clutch_position : float = 1.0 
var current_speed_mps = 0.0
@onready var last_pos = position


var gear_shift_time = 0.2
var gear_timer = 0.0
var throttle_val = 0.0
var brake_val = 0.0

var rotation_angle = 0
var wheelspin = -50000


@onready var l1 = $braketrail/l1
@onready var l2 = $braketrail/l2
@onready var l3 = $braketrail/l3
@onready var l4 = $braketrail/l4

@onready var rr_wheel = get_node("rr")
@onready var rl_wheel = get_node("rl")
@onready var fr_wheel = get_node("fr")
@onready var fl_wheel = get_node("fl")

func get_speed_kph():
	return current_speed_mps * 3600.0 / 1000.0

# RPM of engine based on the current velocity of car
func calculate_rpm() -> float:
	var wheel_circumference : float = 2.0 * PI * $rr.wheel_radius
	var wheel_rotation_speed : float = 60.0 * current_speed_mps / wheel_circumference
	var drive_shaft_rotation_speed : float = wheel_rotation_speed * FinalDriveRatio
	if current_gear == -1:
		return drive_shaft_rotation_speed * -ReverseRatio + IdleRPM
	elif current_gear <= GearRatio.size():
		return drive_shaft_rotation_speed * GearRatio[current_gear - 1] + IdleRPM
	elif current_gear == 0:
		return IdleRPM 
	else:
		return 0.0
		

func aero():
	var drag = DragCoefficient
	var df = Downforce
	
	var veloc = global_transform.basis.orthonormalized()*(linear_velocity)
	apply_torque_impulse(global_transform.basis.orthonormalized()*( Vector3(((-veloc.length()*0.3)),0,0)  ) )
	
	var vx = veloc.x*0.15
	var vy = veloc.z*0.15
	var vz = veloc.y*0.15
	var vl = veloc.length()*0.15
			
	var forc = global_transform.basis.orthonormalized()*(Vector3(1,0,0))*(-vx*drag)
	forc += global_transform.basis.orthonormalized()*(Vector3(0,0,1))*(-vy*drag)
	forc += global_transform.basis.orthonormalized()*(Vector3(0,1,0))*(-vl*df -vz*drag)
	
	if has_node("DRAG_CENTRE"):
		apply_impulse(global_transform.basis.orthonormalized()*($DRAG_CENTRE.translation),forc)
	else:
		apply_central_impulse(forc)
			

func _ready():
	pass

func handbrake():
	var brake_force = -linear_velocity.normalized() * 500
	apply_central_impulse(brake_force)

func _process_gear_inputs(delta : float):
	if gear_timer > 0.0:
		gear_timer = max(0.0, gear_timer - delta)
		clutch_position = 0.0
	else:
		if Input.is_action_pressed("sd") and current_gear > -1:
			current_gear = current_gear - 1
			gear_timer = gear_shift_time
			clutch_position = 0.0
		elif Input.is_action_pressed("su") and current_gear < GearRatio.size():
			current_gear = current_gear + 1
			gear_timer = gear_shift_time
			clutch_position = 0.0
		else:
			clutch_position = 1.0

func _process(delta : float):
	_process_gear_inputs(delta)
	
	var speed = get_speed_kph()
	var rpm = calculate_rpm()
	
	var info = '|%.0f KM/H | %.0f RPM | Gear %d|'  % [ speed, rpm, current_gear ] # .0f no decimals
	
	$"../Label".text = info

func _physics_process(delta):
	current_speed_mps = (position - last_pos).length() / delta
	
	steering = move_toward(steering, Input.get_axis("right","left") * MaxSteer, delta * 2.5)
	throttle_val = 1.0 if Input.get_action_strength("accel") else 0.0
	brake_val = 1.0 if Input.get_action_strength("brakes") else 0.0
	if Input.is_action_pressed("hb"):
			handbrake()
	var rpm = calculate_rpm()
	var rpm_factor = clamp(rpm / MaxRPM, 0.0, 1.0)	
	var power_factor = PowerCurve.sample_baked(rpm_factor)

	if current_gear == -1:
		engine_force = clutch_position * throttle_val * power_factor * ReverseRatio * FinalDriveRatio * MaxEngineForce
	elif current_gear > 0 and current_gear <= GearRatio.size():
		engine_force = clutch_position * throttle_val * power_factor * GearRatio[current_gear - 1] * FinalDriveRatio * MaxEngineForce
	elif current_gear == 0:
		engine_force =  0
				
	brake = brake_val * MaxBrakeForce
	
	if brake_val > 0.1:
		$braketrail/l1.trailOn()
		$braketrail/l2.trailOn()
		$braketrail/l3.trailOn()
		$braketrail/l4.trailOn()

	elif brake_val == 0.0:
		$braketrail/l1.trailOff()
		$braketrail/l2.trailOff()
		$braketrail/l3.trailOff()
		$braketrail/l4.trailOff()
	
	if current_speed_mps < 3:
		$braketrail/l1.killall()
		$braketrail/l2.killall()
		$braketrail/l3.killall()
		$braketrail/l4.killall()
		
	$brakelight.visible = brake_val > 0.1 or current_speed_mps < 1
#	if current_speed_mps > TopSpeed:
#		linear_damp = 0.7
#	else:
#		linear_damp = 0.0 
		
	# remember where I am
	last_pos = position
	
